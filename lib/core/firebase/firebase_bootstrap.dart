import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'firebase_messaging_service.dart';
import 'firebase_remote_config_service.dart';

/// Initializes Firebase Core, Local Emulators (when enabled via dart-define),
/// App Check, Crashlytics (mobile only), and Remote Config defaults.
///
/// Fails gracefully so headless tests or restricted environments never crash
/// at app startup.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool isInitialized = false;

  static const bool useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  static const String _recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_ENTERPRISE_SITE_KEY',
  );

  static const String _appCheckDebugToken = String.fromEnvironment(
    'APP_CHECK_DEBUG_TOKEN',
  );

  static const bool _enableAppCheck = bool.fromEnvironment(
    'ENABLE_APP_CHECK',
    defaultValue: true,
  );

  static Future<void> initialize() async {
    if (isInitialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      isInitialized = true;
    } catch (_) {
      isInitialized = false;
      return;
    }

    if (useEmulators) {
      final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? '10.0.2.2'
          : '127.0.0.1';
      try {
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      } catch (_) {
        /* emulator connection is optional */
      }
    }

    try {
      await _activateAppCheck();
    } catch (_) {
      /* App Check stays best-effort in dev */
    }

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      try {
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(!useEmulators);
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      } catch (_) {
        /* Crashlytics unavailable */
      }
    }

    await FirebaseRemoteConfigService.instance.initialize();
    await FirebaseMessagingService.instance.initialize();
  }

  static Future<void> _activateAppCheck() async {
    if (kIsWeb) {
      if (_recaptchaSiteKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          providerWeb: ReCaptchaEnterpriseProvider(_recaptchaSiteKey),
        );
      } else if (_appCheckDebugToken.isNotEmpty || useEmulators) {
        await FirebaseAppCheck.instance.activate(
          providerWeb: WebDebugProvider(
            debugToken:
                _appCheckDebugToken.isNotEmpty ? _appCheckDebugToken : null,
          ),
        );
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (kDebugMode || useEmulators) {
        if (_appCheckDebugToken.isNotEmpty || useEmulators) {
          await FirebaseAppCheck.instance.activate(
            providerAndroid: AndroidDebugProvider(
              debugToken:
                  _appCheckDebugToken.isNotEmpty ? _appCheckDebugToken : null,
            ),
          );
        }
        return;
      }

      if (_enableAppCheck) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
        );
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      if (kDebugMode || useEmulators) {
        if (_appCheckDebugToken.isNotEmpty || useEmulators) {
          await FirebaseAppCheck.instance.activate(
            providerApple: AppleDebugProvider(
              debugToken:
                  _appCheckDebugToken.isNotEmpty ? _appCheckDebugToken : null,
            ),
          );
        }
        return;
      }

      if (_enableAppCheck) {
        await FirebaseAppCheck.instance.activate(
          providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      }
    }
  }
}
