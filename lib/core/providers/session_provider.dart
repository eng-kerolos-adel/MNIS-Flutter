import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_auth_bridge.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../network/mnis_repository.dart';
import '../storage/secure_session_store.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final repositoryProvider = Provider<MnisRepository>(
  (ref) => MnisRepository(ref.watch(apiClientProvider)),
);

/// The single source of truth for "who is signed in". `null` means signed
/// out; the app should never show citizen data without going through this.
final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionUser?>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<SessionUser?> {
  bool _wiredExpiryHook = false;
  String? _lastLoginNationalId;
  String? _lastLoginPassword;

  bool get hasInMemoryCredentials =>
      (_lastLoginNationalId?.isNotEmpty ?? false) &&
      (_lastLoginPassword?.isNotEmpty ?? false);

  @override
  Future<SessionUser?> build() async {
    if (!_wiredExpiryHook) {
      _wiredExpiryHook = true;
      // If a background refresh ever fails, drop the session synchronously
      // so the UI can navigate to login (see main_shell.dart's ref.listen).
      ref.read(apiClientProvider).onSessionExpired = () {
        unawaited(
          FirebaseAuthBridge.instance
              .clearSession(ref.read(repositoryProvider)),
        );
        SecureSessionStore.instance.clearSession();
        state = const AsyncData(null);
      };
    }
    return _restoreFromStorage();
  }

  Future<SessionUser?> _restoreFromStorage() async {
    final stored = await SecureSessionStore.instance.readRefreshToken();
    if (stored == null) return null;
    try {
      final repo = ref.read(repositoryProvider);
      final r = await repo.refresh(stored);
      ref.read(apiClientProvider).setAccessToken(r.accessToken);
      if (r.refreshToken != null) {
        await SecureSessionStore.instance.writeRefreshToken(r.refreshToken!);
        if (await SecureSessionStore.instance.readBiometricEnabled()) {
          await SecureSessionStore.instance
              .writeBiometricRefreshToken(r.refreshToken!);
        }
      }
      final user = await repo.me();
      unawaited(FirebaseAuthBridge.instance.syncSession(repo, user));
      return user;
    } on ApiException {
      await SecureSessionStore.instance.clearRefreshToken();
      return null;
    } catch (_) {
      // Network unreachable at startup: don't wipe the stored session, just
      // stay signed out for this launch — try again next time there's a signal.
      return null;
    }
  }

  /// Used by the biometric-unlock flow: re-validates the stored refresh
  /// token (does not prompt for a password) and updates [state].
  Future<SessionUser?> restoreForBiometric() async {
    state = const AsyncLoading();
    final user = await _restoreFromStorage();
    state = AsyncData(user);
    return user;
  }

  Future<SessionUser> login(String nationalId, String password) async {
    state = const AsyncLoading();
    final repo = ref.read(repositoryProvider);
    try {
      final r = await repo.login(nationalId, password);
      _lastLoginNationalId = nationalId;
      _lastLoginPassword = password;
      ref.read(apiClientProvider).setAccessToken(r.accessToken);
      if (r.refreshToken != null) {
        await SecureSessionStore.instance.writeRefreshToken(r.refreshToken!);
        if (await SecureSessionStore.instance.readBiometricEnabled()) {
          await SecureSessionStore.instance
              .writeBiometricRefreshToken(r.refreshToken!);
        }
      }
      await SecureSessionStore.instance.saveLastLoginCredentials(
        userId: r.user.id,
        nationalId: nationalId,
        password: password,
      );
      if (await SecureSessionStore.instance.readBiometricEnabled()) {
        final prevBioUserId =
            await SecureSessionStore.instance.readBiometricUserId();
        if (prevBioUserId == null || prevBioUserId == r.user.id) {
          await SecureSessionStore.instance.saveBiometricEnrollment(
            userId: r.user.id,
            nationalId: nationalId,
            password: password,
            refreshToken: r.refreshToken,
          );
        } else {
          await SecureSessionStore.instance.disableBiometricEnrollment();
        }
      }
      state = AsyncData(r.user);
      unawaited(FirebaseAuthBridge.instance.syncSession(repo, r.user));
      return r.user;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<bool> enrollBiometric({
    String? nationalIdOverride,
    String? passwordOverride,
  }) async {
    final user = state.value;
    if (user == null) return false;
    var nid = (nationalIdOverride ?? _lastLoginNationalId)?.trim();
    var pw = passwordOverride ?? _lastLoginPassword;
    if (nid == null || nid.isEmpty || pw == null || pw.isEmpty) {
      final last = await SecureSessionStore.instance.readLastLoginCredentials();
      if (last != null && last.userId == user.id) {
        nid = last.nationalId;
        pw = last.password;
      }
    }
    final currentRefresh = await SecureSessionStore.instance.readRefreshToken();
    await SecureSessionStore.instance.saveBiometricEnrollment(
      userId: user.id,
      nationalId: nid,
      password: pw,
      refreshToken: currentRefresh,
    );
    return true;
  }

  Future<void> disableBiometric() =>
      SecureSessionStore.instance.disableBiometricEnrollment();

  Future<SessionUser?> loginWithBiometric() async {
    final creds = await SecureSessionStore.instance.readBiometricCredentials();
    if (creds != null) {
      try {
        return await login(creds.nationalId, creds.password);
      } catch (_) {
        // Fallback to refresh token if stored password is stale (e.g. changed elsewhere)
      }
    }
    final bioToken =
        await SecureSessionStore.instance.readBiometricRefreshToken() ??
            await SecureSessionStore.instance.readRefreshToken();
    if (bioToken == null || bioToken.isEmpty) return null;
    await SecureSessionStore.instance.writeRefreshToken(bioToken);
    return restoreForBiometric();
  }

  Future<void> changePassword(String current, String next) async {
    await ref.read(repositoryProvider).changePassword(current, next);
    // The backend revokes every session on password change; mirror that locally.
    await logout();
  }

  Future<void> logout() async {
    final repo = ref.read(repositoryProvider);
    final stored = await SecureSessionStore.instance.readRefreshToken();
    final bioEnabled = await SecureSessionStore.instance.readBiometricEnabled();
    _lastLoginNationalId = null;
    _lastLoginPassword = null;
    try {
      await FirebaseAuthBridge.instance.clearSession(repo);
    } catch (_) {}
    if (bioEnabled && stored != null && stored.isNotEmpty) {
      await SecureSessionStore.instance.writeBiometricRefreshToken(stored);
    } else {
      try {
        await repo.logout(stored);
      } catch (_) {
        /* best-effort: still clear locally even if the call fails offline */
      }
    }
    ref.read(apiClientProvider).setAccessToken(null);
    await SecureSessionStore.instance.clearSession();
    state = const AsyncData(null);
  }

  /// Re-fetches `/auth/me` (e.g. after nothing changed but you want to be sure).
  Future<void> refreshUser() async {
    try {
      final user = await ref.read(repositoryProvider).me();
      state = AsyncData(user);
    } catch (_) {
      /* keep whatever we had */
    }
  }
}


