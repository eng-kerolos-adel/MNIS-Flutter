import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/firebase/firebase_analytics_service.dart';
import '../../../../core/firebase/firebase_auth_bridge.dart';
import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/providers/data_providers.dart';
import '../../../../core/providers/notifications_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/biometric_enrollment.dart';
import '../../../../core/utils/providers.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  final _otpCtrl = TextEditingController();

  bool _loadingStatus = true;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _loadError;
  String? _actionError;

  bool _hasPhone = false;
  bool _verified = false;
  String? _phoneE164;
  String? _phoneMasked;
  DateTime? _verifiedAt;

  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;
  ConfirmationResult? _webConfirmation;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  bool get _isAr => ref.read(localeProvider).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _loadError = null;
    });
    try {
      final status = await ref.read(repositoryProvider).fetchPhoneStatus();
      if (!mounted) return;
      final hasPhone = (status['hasPhone'] as bool?) ?? false;
      final verified = (status['verified'] as bool?) ?? false;
      final rawAt = status['verifiedAt'] as String?;
      setState(() {
        _hasPhone = hasPhone;
        _verified = verified;
        _phoneE164 = status['phoneE164'] as String?;
        _phoneMasked = status['phoneMasked'] as String?;
        _verifiedAt = rawAt != null ? DateTime.tryParse(rawAt) : null;
        _loadingStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _loadError = e.toString();
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  Future<void> _sendSmsOtp() async {
    final phone = _phoneE164;
    if (phone == null || phone.isEmpty) return;
    if (!FirebaseBootstrap.isInitialized) {
      _showSnack(
        _isAr
            ? 'خدمة التحقق عبر SMS غير متاحة حالياً على هذا الجهاز.'
            : 'SMS verification service is unavailable on this device.',
      );
      return;
    }

    setState(() {
      _sendingOtp = true;
      _actionError = null;
    });

    try {
      await FirebaseAuth.instance.setLanguageCode(_isAr ? 'ar' : 'en');
      if (kIsWeb) {
        _webConfirmation = null;
        final confirmation =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        if (!mounted) return;
        setState(() {
          _webConfirmation = confirmation;
          _codeSent = true;
          _sendingOtp = false;
        });
        _startCooldown();
        _showSnack(
          _isAr
              ? 'تم إرسال كود التأكيد عبر SMS إلى رقمك المسجل.'
              : 'SMS verification code sent to your registered number.',
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        // Keep verification strictly inside the native app (reCAPTCHA Enterprise
        // RecaptchaTasksClient / Play Integrity) and never force Chrome tabs.
        try {
          await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: false);
        } catch (_) {}
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (credential) {
          unawaited(_completeWithPhoneCredential(credential));
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _sendingOtp = false);
          _setActionError(e);
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _codeSent = true;
            _sendingOtp = false;
          });
          _startCooldown();
          _showSnack(
            _isAr
                ? 'تم إرسال كود التأكيد عبر SMS إلى رقمك المسجل.'
                : 'SMS verification code sent to your registered number.',
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      _setActionError(e);
    }
  }

  Future<void> _verifyOtpCode() async {
    final code = _otpCtrl.text.trim();
    if (code.length < 6) {
      _showSnack(
        _isAr
            ? 'أدخل الكود المكون من 6 أرقام المرسل في رسالة SMS.'
            : 'Enter the 6-digit SMS verification code.',
      );
      return;
    }

    setState(() {
      _verifyingOtp = true;
      _actionError = null;
    });

    try {
      UserCredential cred;
      if (kIsWeb) {
        final conf = _webConfirmation;
        if (conf == null) {
          throw StateError('MISSING_WEB_CONFIRMATION');
        }
        cred = await conf.confirm(code);
      } else {
        final verId = _verificationId;
        if (verId == null || verId.isEmpty) {
          throw StateError('MISSING_VERIFICATION_ID');
        }
        final phoneCred = PhoneAuthProvider.credential(
          verificationId: verId,
          smsCode: code,
        );
        cred = await FirebaseAuth.instance.signInWithCredential(phoneCred);
      }
      await _finishServerVerification(cred);
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifyingOtp = false);
      _setActionError(e);
    }
  }

  Future<void> _completeWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    if (!mounted) return;
    setState(() {
      _sendingOtp = false;
      _verifyingOtp = true;
      _actionError = null;
    });
    try {
      final cred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _finishServerVerification(cred);
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifyingOtp = false);
      _setActionError(e);
    }
  }

  Future<void> _finishServerVerification(UserCredential cred) async {
    final idToken = await cred.user?.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('INVALID_FIREBASE_TOKEN');
    }

    final result = await ref.read(repositoryProvider).verifyPhone(idToken);
    unawaited(FirebaseAnalyticsService.instance.logPhoneVerified());

    final repo = ref.read(repositoryProvider);
    await ref.read(sessionControllerProvider.notifier).refreshUser();
    ref.invalidate(profileProvider);
    ref.invalidate(notificationsProvider);
    final sessionUser = ref.read(sessionControllerProvider).value;
    if (sessionUser != null) {
      unawaited(FirebaseAuthBridge.instance.syncSession(repo, sessionUser));
    }

    if (!mounted) return;
    final rawAt = result['verifiedAt'] as String?;
    setState(() {
      _verified = true;
      _verifiedAt = rawAt != null ? DateTime.tryParse(rawAt) : DateTime.now();
      _verifyingOtp = false;
      _codeSent = false;
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.verified_user_rounded,
          color: AppColors.secondary,
          size: 40,
        ),
        title: Text(
          _isAr ? 'تم تأكيد رقم هاتفك بنجاح' : 'Mobile Number Verified',
        ),
        content: Text(
          _isAr
              ? 'تم التحقق من رقم هاتفك المسجّل لدى الاستقبال وتفعيل حسابك بالكامل في منظومة MNIS.'
              : 'Your reception-registered mobile number has been verified and your MNIS account is now fully active.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    final userId = ref.read(sessionControllerProvider).value?.id;
    if (userId != null) {
      await promptBiometricEnrollmentIfEligible(
        context,
        ref,
        userId,
        forcePrompt: true,
      );
    }
    if (mounted) context.go(AppRoutes.home);
  }

  Future<void> _signOut() async {
    await ref.read(sessionControllerProvider.notifier).logout();
    if (mounted) context.go(AppRoutes.login);
  }

  void _setActionError(Object err) {
    final message = _friendlyError(err);
    if (!mounted) return;
    setState(() => _actionError = message);
    _showSnack(message);
  }

  String _friendlyError(Object err) {
    if (err is FirebaseAuthException) {
      final rawMsg = (err.message ?? '').toLowerCase();
      switch (err.code) {
        case 'operation-not-allowed':
          if (rawMsg.contains('region') || rawMsg.contains('sms')) {
            return _isAr
                ? 'إرسال رسائل SMS لهذه المنطقة غير مفعل حالياً في إعدادات النظام.'
                : 'SMS delivery to this region is currently disabled in project settings.';
          }
          return _isAr
              ? 'خدمة التحقق عبر SMS غير مفعلة حالياً.'
              : 'SMS verification is currently disabled.';
        case 'missing-client-identifier':
        case 'app-not-authorized':
          return _isAr
              ? 'تعذّر التحقق من أمان التطبيق تلقائياً. تأكد من تحديث خدمات Google Play على الهاتف وحاول مرة أخرى.'
              : 'Could not verify app integrity automatically. Ensure Google Play Services is updated and retry.';
        case 'captcha-check-failed':
        case 'web-context-cancelled':
        case 'missing-activity-for-recaptcha':
          return _isAr
              ? 'لم يكتمل التحقق الأمني، يرجى إعادة المحاولة.'
              : 'Security check was cancelled or incomplete. Please retry.';
        case 'unauthorized-domain':
          return _isAr
              ? 'نطاق التشغيل غير مصرح به في إعدادات التحقق.'
              : 'This domain is not authorized for SMS verification.';
        case 'billing-not-enabled':
          return _isAr
              ? 'خدمة إرسال رسائل SMS غير مفعلة في حساب الاستضافة.'
              : 'Live SMS billing is not active on this project.';
        case 'invalid-phone-number':
          return _isAr
              ? 'صيغة رقم الهاتف المسجل غير صالحة، راجع مكتب الاستقبال لتحديثه.'
              : 'Registered phone number format is invalid. Contact reception.';
        case 'quota-exceeded':
          return _isAr
              ? 'تم الوصول للحد الأقصى لرسائل التأكيد الآن، يرجى المحاولة لاحقاً.'
              : 'SMS quota reached. Please try again later.';
        case 'network-request-failed':
          return _isAr
              ? 'تعذّر الاتصال بالإنترنت، تحقق من الشبكة وحاول مرة أخرى.'
              : 'Network error. Check your connection and retry.';
        case 'invalid-verification-code':
          return _isAr
              ? 'الكود المدخل غير صحيح، يرجى التأكد من رسالة SMS.'
              : 'Incorrect SMS verification code.';
        case 'too-many-requests':
          return _isAr
              ? 'تم إرسال طلبات متكررة، يرجى الانتظار بضع دقائق ثم المحاولة.'
              : 'Too many attempts. Please wait a few minutes and try again.';
        case 'session-expired':
          return _isAr
              ? 'انتهت صلاحية كود التحقق، أعد إرسال كود جديد.'
              : 'Verification code expired. Please resend.';
      }
      return err.message ?? (_isAr ? 'تعذّر إرسال الكود' : 'SMS request failed');
    }
    if (err is ApiException) {
      switch (err.code) {
        case 'PHONE_MISMATCH':
          return _isAr
              ? 'الرقم المؤكد لا يطابق رقم الهاتف المسجل لدى مكتب الاستقبال.'
              : 'Verified phone number does not match the number registered at reception.';
        case 'NO_PHONE_REGISTERED':
          return _isAr
              ? 'لم يسجل مكتب الاستقبال رقم هاتف لحسابك بعد.'
              : 'Reception has not registered a mobile number for your account yet.';
        case 'PHONE_ALREADY_USED':
          return _isAr
              ? 'هذا الرقم مرتبط بحساب مواطن آخر، راجع مكتب الاستقبال.'
              : 'This number belongs to another citizen account. Contact reception.';
      }
    }
    return _isAr
        ? 'تعذّر إتمام التحقق، يرجى المحاولة مرة أخرى.'
        : 'Verification could not be completed. Please retry.';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';

    return PopScope(
      canPop: _verified,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          automaticallyImplyLeading: _verified,
          title: Text(
            isAr ? 'تأكيد رقم الهاتف' : 'Verify Mobile Number',
            style: AppTypography.headlineMd.copyWith(color: cs.onSurface),
          ),
          backgroundColor: cs.surface,
          elevation: 0,
          iconTheme: IconThemeData(color: cs.onSurface),
          actions: [
            if (!_verified)
              TextButton.icon(
                onPressed: _signOut,
                icon: Icon(Icons.logout_rounded, size: 18, color: cs.error),
                label: Text(
                  isAr ? 'خروج' : 'Sign out',
                  style: TextStyle(color: cs.error),
                ),
              ),
          ],
        ),
        body: Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: _loadingStatus
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_rounded,
                                size: 48, color: cs.error),
                            const SizedBox(height: 12),
                            Text(
                              isAr
                                  ? 'تعذّر تحميل بيانات الهاتف المسجّل'
                                  : 'Could not load registered mobile status',
                              style: AppTypography.bodyMd,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadStatus,
                              child: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_verified) ...[
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isAr
                                      ? 'الخطوة ٢ من ٢ — تأكيد رقم الهاتف عبر SMS'
                                      : 'Step 2 of 2 — Confirm Mobile via SMS',
                                  style: AppTypography.labelMd.copyWith(
                                    color: cs.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _verified
                                  ? AppColors.secondary.withOpacity(0.1)
                                  : cs.primaryContainer.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _verified
                                    ? AppColors.secondary.withOpacity(0.35)
                                    : cs.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _verified
                                      ? Icons.verified_user_rounded
                                      : Icons.sms_rounded,
                                  size: 48,
                                  color: _verified
                                      ? AppColors.secondary
                                      : cs.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _verified
                                      ? (isAr
                                          ? 'رقم هاتفك موثّق بالكامل'
                                          : 'Mobile Number Verified')
                                      : !_hasPhone
                                          ? (isAr
                                              ? 'لا يوجد رقم هاتف مسجّل بعد'
                                              : 'No Registered Phone Number')
                                          : (isAr
                                              ? 'أكّد رقم هاتفك للمتابعة'
                                              : 'Verify Your Phone to Continue'),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.headlineMd
                                      .copyWith(color: cs.onSurface),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _verified
                                      ? (isAr
                                          ? 'تم تأكيد الرقم ${_phoneMasked ?? ''} عبر رسالة SMS بنجاح.'
                                          : 'Number ${_phoneMasked ?? ''} verified via SMS.')
                                      : !_hasPhone
                                          ? (isAr
                                              ? 'لا يمكنك الدخول للملف الطبي قبل تسجيل رقم هاتفك لدى مكتب الاستقبال وتأكيده برسالة SMS. يرجى مراجعة الاستقبال ثم الضغط على تحديث الحالة.'
                                              : 'Please ask reception to register your unique mobile number first, then tap Refresh Status to verify via SMS.')
                                          : (isAr
                                              ? 'لحماية بياناتك الطبية، أرسل كود التأكيد عبر رسالة SMS إلى رقمك المسجّل لدى الاستقبال (${_phoneMasked ?? ''}) ثم أدخله للمتابعة.'
                                              : 'To protect your medical record, confirm ownership of your reception-registered number (${_phoneMasked ?? ''}) via SMS OTP.'),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySm
                                      .copyWith(color: cs.onSurfaceVariant),
                                ),
                                if (_verified && _verifiedAt != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    DateFormat.yMMMd(locale.languageCode)
                                        .add_jm()
                                        .format(_verifiedAt!),
                                    style: AppTypography.labelSm
                                        .copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_actionError != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.error.withOpacity(0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: cs.onErrorContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _actionError!,
                                      style: AppTypography.bodySm.copyWith(
                                        color: cs.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (!_hasPhone)
                            OutlinedButton.icon(
                              onPressed: _loadStatus,
                              icon: const Icon(Icons.refresh_rounded),
                              label:
                                  Text(isAr ? 'تحديث الحالة' : 'Refresh Status'),
                            ),
                          if (_hasPhone && !_verified) ...[
                            if (!_codeSent)
                              FilledButton.icon(
                                onPressed:
                                    _sendingOtp ? null : () => _sendSmsOtp(),
                                icon: _sendingOtp
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.sms_rounded),
                                label: Text(
                                  isAr
                                      ? 'إرسال كود التأكيد عبر SMS'
                                      : 'Send SMS Verification Code',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                            if (_codeSent) ...[
                              TextField(
                                controller: _otpCtrl,
                                keyboardType: TextInputType.number,
                                textDirection: TextDirection.ltr,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: isAr
                                      ? 'أدخل كود SMS المكون من 6 أرقام'
                                      : 'Enter 6-digit SMS Code',
                                  prefixIcon: const Icon(Icons.pin_rounded),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed:
                                    _verifyingOtp ? null : _verifyOtpCode,
                                icon: _verifyingOtp
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.verified_rounded),
                                label: Text(
                                  isAr
                                      ? 'تأكيد الرقم والدخول'
                                      : 'Verify & Enter App',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed:
                                    (_cooldownSeconds > 0 || _sendingOtp)
                                        ? null
                                        : () => _sendSmsOtp(),
                                child: Text(
                                  _cooldownSeconds > 0
                                      ? (isAr
                                          ? 'إعادة إرسال الكود خلال $_cooldownSeconds ث'
                                          : 'Resend code in ${_cooldownSeconds}s')
                                      : (isAr
                                          ? 'إعادة إرسال كود SMS'
                                          : 'Resend SMS Code'),
                                ),
                              ),
                            ],
                          ],
                          if (_verified)
                            FilledButton.icon(
                              onPressed: () => context.go(AppRoutes.home),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: Text(
                                  isAr ? 'الانتقال للتطبيق' : 'Go to App'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
