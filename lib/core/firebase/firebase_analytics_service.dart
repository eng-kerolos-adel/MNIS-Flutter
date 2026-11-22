import 'package:firebase_analytics/firebase_analytics.dart';

import 'firebase_bootstrap.dart';

/// Logs strictly non-PII product events to Firebase Analytics.
class FirebaseAnalyticsService {
  FirebaseAnalyticsService._();
  static final FirebaseAnalyticsService instance =
      FirebaseAnalyticsService._();

  Future<void> logEvent(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    if (!FirebaseBootstrap.isInitialized) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (_) {}
  }

  Future<void> logPhoneVerified() => logEvent('citizen_phone_verified');

  Future<void> logPushReceived(String type) =>
      logEvent('push_notification_received', {'type': type});

  Future<void> logAiQuery() => logEvent('ai_health_assistant_query');
}
