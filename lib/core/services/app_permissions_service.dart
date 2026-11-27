import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/biometric_enrollment.dart';

enum CapabilityStatus { granted, denied, permanentlyDenied, unavailable }

class AppCapabilitySnapshot {
  final CapabilityStatus location;
  final CapabilityStatus camera;
  final CapabilityStatus notifications;
  final CapabilityStatus sms;
  final CapabilityStatus biometrics;
  final BiometricCapabilities biometricInfo;

  const AppCapabilitySnapshot({
    required this.location,
    required this.camera,
    required this.notifications,
    required this.sms,
    required this.biometrics,
    required this.biometricInfo,
  });
}

/// Manages strictly the 5 real permissions used by MNIS:
/// 1) Biometrics (Fingerprint & Face Unlock)
/// 2) Live Location (GPS Clinic/Lab Filtering)
/// 3) Camera (Document / Medical Record Capture)
/// 4) Notifications (Appointments, Labs & Periodic Medication Reminders)
/// 5) SMS (Seamless In-App Phone OTP Verification)
class AppPermissionsService {
  AppPermissionsService._();
  static final AppPermissionsService instance = AppPermissionsService._();

  CapabilityStatus _mapPerm(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) {
      return CapabilityStatus.granted;
    }
    if (s.isPermanentlyDenied || s.isRestricted) {
      return CapabilityStatus.permanentlyDenied;
    }
    return CapabilityStatus.denied;
  }

  Future<CapabilityStatus> checkLocation() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
        return CapabilityStatus.granted;
      }
      if (p == LocationPermission.deniedForever) {
        return CapabilityStatus.permanentlyDenied;
      }
      if (p == LocationPermission.unableToDetermine) {
        return CapabilityStatus.unavailable;
      }
      return CapabilityStatus.denied;
    } catch (_) {
      return CapabilityStatus.unavailable;
    }
  }

  Future<CapabilityStatus> requestLocation() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
        return CapabilityStatus.granted;
      }
      if (p == LocationPermission.deniedForever) {
        return CapabilityStatus.permanentlyDenied;
      }
      return CapabilityStatus.denied;
    } catch (_) {
      return CapabilityStatus.unavailable;
    }
  }

  Future<CapabilityStatus> requestCamera() async {
    if (kIsWeb) return CapabilityStatus.granted;
    try {
      return _mapPerm(await Permission.camera.request());
    } catch (_) {
      return CapabilityStatus.unavailable;
    }
  }

  Future<CapabilityStatus> requestNotifications() async {
    if (kIsWeb) return CapabilityStatus.granted;
    try {
      return _mapPerm(await Permission.notification.request());
    } catch (_) {
      return CapabilityStatus.unavailable;
    }
  }

  Future<CapabilityStatus> requestSms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return CapabilityStatus.granted;
    }
    try {
      return _mapPerm(await Permission.sms.request());
    } catch (_) {
      return CapabilityStatus.unavailable;
    }
  }

  Future<AppCapabilitySnapshot> checkAll() async {
    final loc = await checkLocation();
    final bioInfo = await getBiometricCapabilities(LocalAuthentication());
    final bioStatus = bioInfo.available
        ? CapabilityStatus.granted
        : CapabilityStatus.unavailable;

    if (kIsWeb) {
      return AppCapabilitySnapshot(
        location: loc,
        camera: CapabilityStatus.granted,
        notifications: CapabilityStatus.granted,
        sms: CapabilityStatus.granted,
        biometrics: bioStatus,
        biometricInfo: bioInfo,
      );
    }

    PermissionStatus cam = PermissionStatus.denied;
    PermissionStatus notif = PermissionStatus.denied;
    PermissionStatus sms = PermissionStatus.granted;
    try {
      cam = await Permission.camera.status;
    } catch (_) {}
    try {
      notif = await Permission.notification.status;
    } catch (_) {}
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        sms = await Permission.sms.status;
      } catch (_) {}
    }

    return AppCapabilitySnapshot(
      location: loc,
      camera: _mapPerm(cam),
      notifications: _mapPerm(notif),
      sms: _mapPerm(sms),
      biometrics: bioStatus,
      biometricInfo: bioInfo,
    );
  }

  Future<bool> openDeviceSettings() async {
    if (kIsWeb) return false;
    return openAppSettings();
  }
}
