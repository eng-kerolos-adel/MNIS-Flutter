import 'package:flutter/foundation.dart';

/// Where the app talks to the MNIS backend.
///
/// Uses `--dart-define=API_BASE_URL=...` when provided. In release builds
/// defaults to the Firebase Hosting production gateway (`mnis-egypt-dev.web.app`
/// which rewrites `/v1/**` to the Cloud Function), and in debug/profile builds
/// defaults to local emulator/host ports for development.
abstract class Env {
  static const String _defined = String.fromEnvironment('API_BASE_URL');
  static const String _productionApiUrl = 'https://mnis-egypt-dev.web.app';

  static String get apiBaseUrl {
    if (_defined.isNotEmpty) return _defined;
    if (kReleaseMode) return _productionApiUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3001';
    }
    return 'http://localhost:3001';
  }
}
