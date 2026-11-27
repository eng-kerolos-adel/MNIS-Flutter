import 'package:flutter/material.dart';

class SmsBridgeException implements Exception {
  final String code;
  final String message;

  const SmsBridgeException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// Web stub (Web calls `FirebaseAuth.instance.signInWithPhoneNumber` directly).
class InAppSmsBridgeController {
  InAppSmsBridgeController({
    required this.isAr,
    required this.isDark,
    this.onCodeSent,
    this.onVerified,
    this.onError,
    this.onVerifyError,
  });

  final bool isAr;
  final bool isDark;
  final VoidCallback? onCodeSent;
  final ValueChanged<String>? onVerified;
  final void Function(String code, String message)? onError;
  final void Function(String code, String message)? onVerifyError;

  final ValueNotifier<bool> challengeVisible = ValueNotifier<bool>(false);
  bool get isSupported => false;

  Future<void> sendSms(String phoneE164, {required bool isAr}) async {}
  Future<void> confirmOtp(String code) async {}
  Future<void> cancelChallenge() async {}
  Future<void> reset() async {}
  void dispose() {
    challengeVisible.dispose();
  }
}

class InAppSmsBridgeHost extends StatelessWidget {
  const InAppSmsBridgeHost({super.key, required this.controller});
  final InAppSmsBridgeController controller;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
