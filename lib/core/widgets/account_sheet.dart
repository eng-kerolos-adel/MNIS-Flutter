import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../firebase/firebase_ai_service.dart';
import '../firebase/firebase_analytics_service.dart';
import '../firebase/firebase_remote_config_service.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_provider.dart';
import '../router/app_router.dart';
import '../storage/secure_session_store.dart';
import '../theme/app_typography.dart';
import '../utils/biometric_enrollment.dart';
import '../utils/error_messages.dart';
import '../utils/providers.dart';
import 'patient_avatar.dart';

/// The account/profile bottom sheet reachable from the avatar button on every
/// main screen: who's signed in, quick links, change password and sign out.
Future<void> showAccountSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AccountSheet(),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final session = ref.watch(sessionControllerProvider).value;
    final profileAsync = ref.watch(profileProvider);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                PatientAvatar(
                  url: profileAsync.value?.photoUrl,
                  size: 52,
                  borderRadius: BorderRadius.circular(14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profileAsync.value?.fullName.pick(
                                Locale(isAr ? 'ar' : 'en')) ??
                            (isAr ? session?.fullNameAr : session?.fullNameEn) ??
                            '',
                        style: AppTypography.headlineSm
                            .copyWith(color: cs.onSurface),
                      ),
                      if (profileAsync.value != null)
                        Text('MTI: ${profileAsync.value!.mti}',
                            style: AppTypography.labelSm
                                .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            _Tile(
              icon: Icons.event_available_rounded,
              label: l.appointmentsMenu,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.appointments);
              },
            ),
            _Tile(
              icon: Icons.qr_code_rounded,
              label: l.shareWithDoctor,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.shareRecord);
              },
            ),
            _Tile(
              icon: Icons.upload_file_rounded,
              label: l.myDocuments,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.documents);
              },
            ),
            _Tile(
              icon: (profileAsync.value?.isPhoneVerified ?? false)
                  ? Icons.verified_user_rounded
                  : Icons.sms_rounded,
              label: (profileAsync.value?.isPhoneVerified ?? false)
                  ? (isAr ? 'الهوية موثّقة عبر SMS ✓' : 'Phone Verified via SMS ✓')
                  : (isAr
                      ? 'تأكيد الهوية برقم الهاتف (SMS)'
                      : 'Confirm Identity via SMS'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.verifyPhone);
              },
            ),
            if (FirebaseRemoteConfigService.instance.aiHealthAssistantEnabled)
              _Tile(
                icon: Icons.auto_awesome_rounded,
                label: isAr
                    ? 'المساعد الصحي الذكي (Gemini AI)'
                    : 'AI Health Assistant (Gemini)',
                onTap: () {
                  final parentCtx = Navigator.of(context).context;
                  Navigator.pop(context);
                  _showAiAssistantDialog(parentCtx, isAr: isAr);
                },
              ),
            const _BiometricToggleTile(),
            _Tile(
              icon: Icons.password_rounded,
              label: l.changePassword,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.changePassword);
              },
            ),
            _Tile(
              icon: Icons.logout_rounded,
              label: l.logout,
              destructive: true,
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l.logoutConfirmTitle),
                    content: Text(l.logoutConfirmBody),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.cancel)),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.logout)),
                    ],
                  ),
                );
                if (confirm != true) return;
                await ref.read(sessionControllerProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.pop(context);
                  context.go(AppRoutes.login);
                }
              },
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: destructive ? cs.error : cs.secondary),
      title: Text(label, style: AppTypography.bodyMd.copyWith(color: color)),
      onTap: onTap,
    );
  }
}

class _BiometricToggleTile extends ConsumerStatefulWidget {
  const _BiometricToggleTile();

  @override
  ConsumerState<_BiometricToggleTile> createState() =>
      _BiometricToggleTileState();
}

class _BiometricToggleTileState extends ConsumerState<_BiometricToggleTile> {
  final _localAuth = LocalAuthentication();
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final supported = await isBiometricHardwareAvailable(_localAuth);
      final userId = ref.read(sessionControllerProvider).value?.id;
      final enabled = userId != null
          ? await SecureSessionStore.instance.isBiometricEnrolledForUser(userId)
          : await SecureSessionStore.instance.hasBiometricCredentials();
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _enabled = enabled;
      });
    } catch (_) {
      if (mounted) setState(() => _supported = false);
    }
  }

  Future<void> _toggle(bool next) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final isAr = l.isArabic;
    final notifier = ref.read(sessionControllerProvider.notifier);

    if (!next) {
      setState(() => _busy = true);
      await notifier.disableBiometric();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            isAr ? 'تم إيقاف تسجيل الدخول بالبصمة' : 'Biometric sign-in disabled',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final authenticated = await authenticateWithBiometrics(
      _localAuth,
      reason: isAr
          ? 'امسح بصمتك لتفعيل تسجيل الدخول بالبصمة'
          : 'Scan your fingerprint to enable biometric sign-in',
    );
    if (!mounted) return;
    if (!authenticated) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.biometricFailed)),
      );
      return;
    }

    await notifier.enrollBiometric();
    final enrolled = await SecureSessionStore.instance.hasBiometricCredentials();
    if (enrolled) {
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _busy = false;
      });
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
      return;
    }

    final profileNid = ref.read(profileProvider).value?.nationalId ?? '';
    final nidCtrl = TextEditingController(text: profileNid);
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAr ? 'تأكيد كلمة المرور لتفعيل البصمة' : 'Confirm Password',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (profileNid.isEmpty) ...[
              TextField(
                controller: nidCtrl,
                keyboardType: TextInputType.number,
                maxLength: 14,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l.nationalIdLabel,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: l.passwordLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.enable),
          ),
        ],
      ),
    );
    final nid = nidCtrl.text.trim();
    final pw = passCtrl.text;
    nidCtrl.dispose();
    passCtrl.dispose();

    if (confirmed != true || nid.length != 14 || pw.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      await notifier.login(nid, pw);
      await notifier.enrollBiometric(
        nationalIdOverride: nid,
        passwordOverride: pw,
      );
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _busy = false;
      });
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, isAr: isAr))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(Icons.fingerprint_rounded, color: cs.secondary),
      title: Text(
        isAr ? 'تسجيل الدخول بالبصمة' : 'Biometric Sign-In',
        style: AppTypography.bodyMd.copyWith(color: cs.onSurface),
      ),
      subtitle: Text(
        _enabled
            ? (isAr ? 'مفعّل — ادخل ببصمتك مباشرة' : 'Enabled for instant login')
            : (isAr ? 'معطّل' : 'Disabled'),
        style: AppTypography.labelSm.copyWith(color: cs.onSurfaceVariant),
      ),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}

void _showAiAssistantDialog(BuildContext context, {required bool isAr}) {
  showDialog<void>(
    context: context,
    builder: (_) => _AiAssistantDialog(isAr: isAr),
  );
}

class _AiAssistantDialog extends StatefulWidget {
  final bool isAr;
  const _AiAssistantDialog({required this.isAr});

  @override
  State<_AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<_AiAssistantDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _answer;
  String? _disclaimer;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await FirebaseAiService.instance.explainMedicalInfo(
        q,
        arabic: widget.isAr,
      );
      unawaited(FirebaseAnalyticsService.instance.logAiQuery());
      if (!mounted) return;
      setState(() {
        _answer = res.text;
        _disclaimer = res.disclaimer;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('PII_NATIONAL_ID_NOT_ALLOWED')
          ? (widget.isAr
              ? 'لا يمكن إرسال الرقم القومي للذكاء الاصطناعي حفاظاً على خصوصيتك.'
              : 'National ID numbers cannot be sent to the AI assistant.')
          : (widget.isAr
              ? 'الخدمة الذكية غير متاحة حالياً (تحقق من تفعيل AI Logic وربط جلسة Firebase).'
              : 'AI assistant is currently unavailable (ensure AI Logic & Firebase Auth are enabled).');
      setState(() {
        _error = msg;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.isAr
            ? 'المساعد الصحي الذكي (Gemini)'
            : 'AI Health Assistant (Gemini)',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: widget.isAr
                      ? 'اسأل عن مصطلح طبي أو نصيحة صحية عامة (بدون رقم قومي)...'
                      : 'Ask about a medical term or general health info (no National ID)...',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
              ],
              if (_answer != null) ...[
                const SizedBox(height: 12),
                Text(_answer!, style: AppTypography.bodySm),
                if (_disclaimer != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _disclaimer!,
                    style: AppTypography.labelSm
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.isAr ? 'إغلاق' : 'Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _ask,
          child: Text(
            _busy
                ? (widget.isAr ? 'جاري التحليل...' : 'Thinking...')
                : (widget.isAr ? 'اسأل المساعد' : 'Ask AI'),
          ),
        ),
      ],
    );
  }
}


