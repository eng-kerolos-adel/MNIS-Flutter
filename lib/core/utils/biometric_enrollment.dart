import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../providers/session_provider.dart';
import '../storage/secure_session_store.dart';

/// Checks whether the device supports local biometrics or screen-lock unlock
/// cleanly across Android Class 2/Class 3 sensors.
Future<bool> isBiometricHardwareAvailable(LocalAuthentication localAuth) async {
  if (kIsWeb) return false;
  try {
    final supported = await localAuth.isDeviceSupported();
    final canCheck = await localAuth.canCheckBiometrics;
    final available = await localAuth.getAvailableBiometrics();
    return supported || canCheck || available.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Runs native Android/iOS biometric/device authentication with `biometricOnly: false`
/// so Class 2 sensors and device PIN/pattern fallback work reliably.
Future<bool> authenticateWithBiometrics(
  LocalAuthentication localAuth, {
  required String reason,
}) async {
  if (kIsWeb) return false;
  try {
    return await localAuth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}

/// Prompts the citizen after both password sign-in and SMS verification are
/// complete to enroll device biometrics (fingerprint/face) for quick sign-in.
Future<void> promptBiometricEnrollmentIfEligible(
  BuildContext context,
  WidgetRef ref,
  String userId, {
  bool forcePrompt = false,
}) async {
  if (kIsWeb) return;

  final notifier = ref.read(sessionControllerProvider.notifier);
  if (await SecureSessionStore.instance.isBiometricEnrolledForUser(userId)) {
    if (notifier.hasInMemoryCredentials) {
      await notifier.enrollBiometric();
    }
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final promptedKey = 'mnis.biometricPrompted.$userId';
  if (!forcePrompt && (prefs.getBool(promptedKey) ?? false)) return;

  final localAuth = LocalAuthentication();
  final canCheck = await isBiometricHardwareAvailable(localAuth);
  if (!canCheck || !context.mounted) return;

  final l = AppLocalizations.of(context);
  final isAr = l.isArabic;
  final enable = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.fingerprint_rounded, size: 36),
      title: Text(l.enableBiometricTitle),
      content: Text(
        isAr
            ? 'الآن بعد تأكيد حسابك وهاتفك بنجاح، يمكنك تفعيل الدخول بالبصمة لتسجيل الدخول لاحقاً بلمسة واحدة دون كتابة الرقم القومي وكلمة المرور.'
            : 'Now that your account and phone are verified, enable fingerprint sign-in to access MNIS next time without typing your National ID and password.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.notNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.enable),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (enable != true) {
    await prefs.setBool(promptedKey, true);
    return;
  }

  final authenticated = await authenticateWithBiometrics(
    localAuth,
    reason: isAr
        ? 'امسح بصمتك لتفعيل تسجيل الدخول بالبصمة'
        : 'Scan your fingerprint to enable biometric sign-in',
  );
  if (!authenticated) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.biometricFailed)),
      );
    }
    return;
  }

  await prefs.setBool(promptedKey, true);
  await notifier.enrollBiometric();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          isAr
              ? 'تم تفعيل تسجيل الدخول بالبصمة بنجاح ✓'
              : 'Biometric sign-in enabled ✓',
        ),
      ),
    );
  }
}
