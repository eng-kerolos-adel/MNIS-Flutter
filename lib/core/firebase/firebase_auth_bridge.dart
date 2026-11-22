import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../network/mnis_repository.dart';
import 'firebase_bootstrap.dart';

/// Synchronizes the primary MNIS session with Firebase Custom Auth,
/// Crashlytics (pseudonymous user UUID only), and FCM device token registration.
class FirebaseAuthBridge {
  FirebaseAuthBridge._();
  static final FirebaseAuthBridge instance = FirebaseAuthBridge._();

  static const String _webVapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');

  String? _lastRegisteredFcmToken;
  StreamSubscription<String>? _tokenRefreshSub;

  Future<void> syncSession(MnisRepository repo, SessionUser user) async {
    if (!FirebaseBootstrap.isInitialized || user.mustChangePassword) return;

    if (!kIsWeb) {
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(user.id);
      } catch (_) {}
    }

    await _registerMessagingToken(repo);

    try {
      if (FirebaseAuth.instance.currentUser?.uid != user.id) {
        final customToken = await repo.fetchFirebaseCustomToken();
        await FirebaseAuth.instance.signInWithCustomToken(customToken);
      }
    } catch (_) {
      /* best-effort Firebase custom auth sync */
    }
  }

  Future<void> _registerMessagingToken(MnisRepository repo) async {
    if (kIsWeb && _webVapidKey.isEmpty) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = kIsWeb
          ? await messaging.getToken(vapidKey: _webVapidKey)
          : await messaging.getToken();
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      if (token != null && token.isNotEmpty && token != _lastRegisteredFcmToken) {
        _lastRegisteredFcmToken = token;
        await repo.registerPushToken(token, platform);
      }
      _tokenRefreshSub ??= messaging.onTokenRefresh.listen((fresh) async {
        if (fresh.isEmpty) return;
        _lastRegisteredFcmToken = fresh;
        try {
          await repo.registerPushToken(fresh, platform);
        } catch (_) {}
      });
    } catch (_) {
      /* FCM registration skipped gracefully on emulators/unsupported devices */
    }
  }

  Future<void> clearSession(MnisRepository repo) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    final staleToken = _lastRegisteredFcmToken;
    _lastRegisteredFcmToken = null;
    if (staleToken != null) {
      try {
        await repo.unregisterPushToken(staleToken);
      } catch (_) {}
    }

    if (!FirebaseBootstrap.isInitialized) return;

    if (!kIsWeb) {
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier('');
      } catch (_) {}
    }

    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (_) {}
  }
}
