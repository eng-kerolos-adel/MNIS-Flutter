import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class FirebaseRemoteConfigService {
  FirebaseRemoteConfigService._();
  static final FirebaseRemoteConfigService instance =
      FirebaseRemoteConfigService._();

  static const Map<String, Object> _defaults = {
    'maintenance_mode': false,
    'maintenance_message_ar':
        'جاري إجراء صيانة دورية للمنظومة، نعود خلال دقائق.',
    'maintenance_message_en':
        'Scheduled system maintenance in progress. We will be back shortly.',
    'min_supported_app_version': '1.0.0',
    'ai_health_assistant_enabled': true,
    'ai_gemini_model': 'gemini-3.8-flash',
    'realtime_queue_sync_enabled': true,
    'emergency_qr_ttl_minutes': 15,
  };

  FirebaseRemoteConfig? _rc;

  Future<void> initialize() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? const Duration(minutes: 1)
              : const Duration(hours: 1),
        ),
      );
      await rc.setDefaults(_defaults);
      _rc = rc;
      // Non-blocking background refresh so launch never stalls.
      unawaited(rc.fetchAndActivate().catchError((_) => false));
    } catch (_) {
      _rc = null;
    }
  }

  bool get maintenanceMode => _rc?.getBool('maintenance_mode') ?? false;

  String get maintenanceMessageAr {
    final v = _rc?.getString('maintenance_message_ar') ?? '';
    return v.isNotEmpty ? v : _defaults['maintenance_message_ar']! as String;
  }

  String get maintenanceMessageEn {
    final v = _rc?.getString('maintenance_message_en') ?? '';
    return v.isNotEmpty ? v : _defaults['maintenance_message_en']! as String;
  }

  String get minSupportedAppVersion {
    final v = _rc?.getString('min_supported_app_version') ?? '';
    return v.isNotEmpty
        ? v
        : _defaults['min_supported_app_version']! as String;
  }

  bool get aiHealthAssistantEnabled =>
      _rc?.getBool('ai_health_assistant_enabled') ?? true;

  String get aiGeminiModel {
    final v = _rc?.getString('ai_gemini_model') ?? '';
    return v.isNotEmpty ? v : _defaults['ai_gemini_model']! as String;
  }

  bool get realtimeQueueSyncEnabled =>
      _rc?.getBool('realtime_queue_sync_enabled') ?? true;

  int get emergencyQrTtlMinutes {
    final v = _rc?.getInt('emergency_qr_ttl_minutes') ?? 0;
    return v > 0 ? v : _defaults['emergency_qr_ttl_minutes']! as int;
  }
}
