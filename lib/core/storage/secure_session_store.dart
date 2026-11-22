import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything persisted on-device for session continuity and offline emergency
/// access. Only the refresh token and small cached JSON blobs live here — the
/// access token itself is kept in memory only (see [ApiClient]) and is never
/// written to disk.
class SecureSessionStore {
  SecureSessionStore._();
  static final SecureSessionStore instance = SecureSessionStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static const _kRefreshToken = 'mnis.refreshToken';
  static const _kEmergencyCache = 'mnis.emergencyCache';
  static const _kEmergencyCachedAt = 'mnis.emergencyCachedAt';
  static const _kProfileCache = 'mnis.profileCache';
  static const _kBiometricEnabled = 'mnis.biometricEnabled';
  static const _kBiometricUserId = 'mnis.biometricUserId';
  static const _kBiometricNationalId = 'mnis.biometricNationalId';
  static const _kBiometricPassword = 'mnis.biometricPassword';
  static const _kBiometricRefreshToken = 'mnis.biometricRefreshToken';
  static const _kLastLoginUserId = 'mnis.lastLoginUserId';
  static const _kLastLoginNationalId = 'mnis.lastLoginNationalId';
  static const _kLastLoginPassword = 'mnis.lastLoginPassword';

  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);
  Future<void> clearRefreshToken() => _storage.delete(key: _kRefreshToken);

  Future<void> cacheEmergencyCardJson(String json) async {
    await _storage.write(key: _kEmergencyCache, value: json);
    await _storage.write(
      key: _kEmergencyCachedAt,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<String?> readEmergencyCardJson() =>
      _storage.read(key: _kEmergencyCache);
  Future<DateTime?> readEmergencyCachedAt() async {
    final raw = await _storage.read(key: _kEmergencyCachedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> cacheProfileJson(String json) =>
      _storage.write(key: _kProfileCache, value: json);
  Future<String?> readProfileJson() => _storage.read(key: _kProfileCache);

  Future<bool> readBiometricEnabled() async =>
      (await _storage.read(key: _kBiometricEnabled)) == 'true';
  Future<void> writeBiometricEnabled(bool enabled) =>
      _storage.write(key: _kBiometricEnabled, value: enabled.toString());

  Future<void> saveLastLoginCredentials({
    required String userId,
    required String nationalId,
    required String password,
  }) async {
    await _storage.write(key: _kLastLoginUserId, value: userId);
    await _storage.write(key: _kLastLoginNationalId, value: nationalId);
    await _storage.write(key: _kLastLoginPassword, value: password);
  }

  Future<({String userId, String nationalId, String password})?>
      readLastLoginCredentials() async {
    final userId = await _storage.read(key: _kLastLoginUserId);
    final nationalId = await _storage.read(key: _kLastLoginNationalId);
    final password = await _storage.read(key: _kLastLoginPassword);
    if (userId == null ||
        userId.isEmpty ||
        nationalId == null ||
        nationalId.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return (userId: userId, nationalId: nationalId, password: password);
  }

  Future<void> writeBiometricRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _kBiometricRefreshToken);
      return;
    }
    await _storage.write(key: _kBiometricRefreshToken, value: token);
  }

  Future<String?> readBiometricRefreshToken() =>
      _storage.read(key: _kBiometricRefreshToken);

  Future<String?> readBiometricUserId() => _storage.read(key: _kBiometricUserId);

  Future<void> saveBiometricEnrollment({
    required String userId,
    String? nationalId,
    String? password,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kBiometricEnabled, value: 'true');
    await _storage.write(key: _kBiometricUserId, value: userId);
    if (nationalId != null &&
        nationalId.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      await _storage.write(key: _kBiometricNationalId, value: nationalId);
      await _storage.write(key: _kBiometricPassword, value: password);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _kBiometricRefreshToken, value: refreshToken);
    }
  }

  Future<void> disableBiometricEnrollment() async {
    await _storage.write(key: _kBiometricEnabled, value: 'false');
    await _storage.delete(key: _kBiometricUserId);
    await _storage.delete(key: _kBiometricNationalId);
    await _storage.delete(key: _kBiometricPassword);
    await _storage.delete(key: _kBiometricRefreshToken);
  }

  Future<({String userId, String nationalId, String password})?>
      readBiometricCredentials() async {
    if (!await readBiometricEnabled()) return null;
    final userId = await _storage.read(key: _kBiometricUserId);
    final nationalId = await _storage.read(key: _kBiometricNationalId);
    final password = await _storage.read(key: _kBiometricPassword);
    if (userId == null ||
        userId.isEmpty ||
        nationalId == null ||
        nationalId.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return (userId: userId, nationalId: nationalId, password: password);
  }

  Future<bool> isBiometricEnrolledForUser(String userId) async {
    if (!await readBiometricEnabled()) return false;
    final storedUserId = await _storage.read(key: _kBiometricUserId);
    if (storedUserId != userId) return false;
    return await readBiometricCredentials() != null ||
        await readBiometricRefreshToken() != null ||
        await readRefreshToken() != null;
  }

  Future<bool> hasBiometricCredentials() async {
    if (!await readBiometricEnabled()) return false;
    return await readBiometricCredentials() != null ||
        await readBiometricRefreshToken() != null ||
        await readRefreshToken() != null;
  }

  /// Called on logout / forced sign-out. Emergency cache is intentionally
  /// kept so the offline emergency card still works right after a sign-out
  /// (e.g. the phone is later used in an emergency); it is only replaced by
  /// a fresh login, never silently wiped.
  Future<void> clearSession() async {
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kProfileCache);
  }
}



