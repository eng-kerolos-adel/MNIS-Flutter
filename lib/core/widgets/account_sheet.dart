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
import '../services/app_permissions_service.dart';
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
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 540),
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _AccountSheet(),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  void _popAndNavigate(BuildContext context, String route) {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context, rootNavigator: true).pop();
    if (router != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRoutes.navigateWithRouter(router, route);
      });
    }
  }

  void _popAndShow(
    BuildContext context,
    void Function(BuildContext hostContext) show,
  ) {
    final hostCtx = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context, rootNavigator: true).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hostCtx.mounted) show(hostCtx);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final session = ref.watch(sessionControllerProvider).value;
    final profileAsync = ref.watch(profileProvider);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SafeArea(
            top: false,
            child: Container(
              key: const Key('account-sheet-card'),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Material(
              type: MaterialType.transparency,
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
                                    (isAr
                                        ? session?.fullNameAr
                                        : session?.fullNameEn) ??
                                    '',
                                style: AppTypography.headlineSm
                                    .copyWith(color: cs.onSurface),
                              ),
                              if (profileAsync.value != null)
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    'MTI: ${profileAsync.value!.mti}',
                                    style: AppTypography.labelSm
                                        .copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
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
                      onTap: () =>
                          _popAndNavigate(context, AppRoutes.appointments),
                    ),
                    _Tile(
                      icon: Icons.qr_code_rounded,
                      label: l.shareWithDoctor,
                      onTap: () =>
                          _popAndNavigate(context, AppRoutes.shareRecord),
                    ),
                    _Tile(
                      icon: Icons.upload_file_rounded,
                      label: l.myDocuments,
                      onTap: () =>
                          _popAndNavigate(context, AppRoutes.documents),
                    ),
                    _Tile(
                      icon: (profileAsync.value?.isPhoneVerified ?? false)
                          ? Icons.verified_user_rounded
                          : Icons.sms_rounded,
                      label: (profileAsync.value?.isPhoneVerified ?? false)
                          ? (isAr
                              ? 'الهوية موثّقة عبر SMS ✓'
                              : 'Phone Verified via SMS ✓')
                          : (isAr
                              ? 'تأكيد الهوية برقم الهاتف (SMS)'
                              : 'Confirm Identity via SMS'),
                      onTap: () =>
                          _popAndNavigate(context, AppRoutes.verifyPhone),
                    ),
                    if (FirebaseRemoteConfigService
                        .instance.aiHealthAssistantEnabled)
                      _Tile(
                        icon: Icons.auto_awesome_rounded,
                        label: isAr
                            ? 'المساعد الصحي الذكي (Gemini AI)'
                            : 'AI Health Assistant (Gemini)',
                        onTap: () => _popAndShow(
                          context,
                          (hostCtx) =>
                              _showAiAssistantDialog(hostCtx, isAr: isAr),
                        ),
                      ),
                    const _BiometricToggleTile(),
                    _Tile(
                      icon: Icons.verified_user_outlined,
                      label: isAr
                          ? 'صلاحيات التطبيق (5 صلاحيات فقط)'
                          : 'Scoped App Permissions (5 Only)',
                      onTap: () => _popAndShow(
                        context,
                        (hostCtx) =>
                            _showPermissionsManagerSheet(hostCtx, isAr: isAr),
                      ),
                    ),
                    _Tile(
                      icon: Icons.password_rounded,
                      label: l.changePassword,
                      onTap: () =>
                          _popAndNavigate(context, AppRoutes.changePassword),
                    ),
                    _Tile(
                      icon: Icons.logout_rounded,
                      label: l.logout,
                      destructive: true,
                      onTap: () async {
                        final router = GoRouter.maybeOf(context);
                        final notifier =
                            ref.read(sessionControllerProvider.notifier);
                        final confirm = await showDialog<bool>(
                          context: context,
                          useRootNavigator: true,
                          builder: (ctx) => Directionality(
                            textDirection:
                                isAr ? TextDirection.rtl : TextDirection.ltr,
                            child: AlertDialog(
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
                          ),
                        );
                        if (confirm != true) return;
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                        await notifier.logout();
                        router?.go(AppRoutes.login);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
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
  BiometricCapabilities _bioCaps = const BiometricCapabilities(
    available: false,
    hasFace: false,
    hasFingerprint: false,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final caps = await getBiometricCapabilities(_localAuth);
      final userId = ref.read(sessionControllerProvider).value?.id;
      final enabled = userId != null
          ? await SecureSessionStore.instance.isBiometricEnrolledForUser(userId)
          : await SecureSessionStore.instance.hasBiometricCredentials();
      if (!mounted) return;
      setState(() {
        _supported = caps.available;
        _enabled = enabled;
        _bioCaps = caps;
      });
    } catch (_) {
      if (mounted) setState(() => _supported = false);
    }
  }

  Future<void> _toggle(bool next) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final isAr = l.isArabic;
    final bioLabel = _bioCaps.label(isAr);
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
            isAr
                ? 'تم إيقاف تسجيل الدخول عبر $bioLabel'
                : '$bioLabel sign-in disabled',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final authenticated = await authenticateWithBiometrics(
      _localAuth,
      reason: isAr
          ? 'تحقق عبر $bioLabel لتفعيل تسجيل الدخول السريع'
          : 'Verify with $bioLabel to enable quick sign-in',
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
                ? 'تم تفعيل الدخول عبر $bioLabel بنجاح ✓'
                : '$bioLabel sign-in enabled ✓',
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
      secondary: Icon(
        _bioCaps.hasFace && !_bioCaps.hasFingerprint
            ? Icons.face_rounded
            : Icons.fingerprint_rounded,
        color: cs.secondary,
      ),
      title: Text(
        isAr
            ? 'تسجيل الدخول بـ ${_bioCaps.label(true)}'
            : '${_bioCaps.label(false)} Sign-In',
        style: AppTypography.bodyMd.copyWith(color: cs.onSurface),
      ),
      subtitle: Text(
        _enabled
            ? (isAr ? 'مفعّل — دخول فوري بدون كلمة مرور' : 'Enabled for instant login')
            : (isAr ? 'معطّل' : 'Disabled'),
        style: AppTypography.labelSm.copyWith(color: cs.onSurfaceVariant),
      ),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}

void _showPermissionsManagerSheet(BuildContext context, {required bool isAr}) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: Colors.transparent,
    builder: (_) => _PermissionsManagerSheet(isAr: isAr),
  );
}

class _PermissionsManagerSheet extends StatefulWidget {
  final bool isAr;
  const _PermissionsManagerSheet({required this.isAr});

  @override
  State<_PermissionsManagerSheet> createState() =>
      _PermissionsManagerSheetState();
}

class _PermissionsManagerSheetState extends State<_PermissionsManagerSheet> {
  AppCapabilitySnapshot? _snap;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    AppCapabilitySnapshot snap;
    try {
      snap = await AppPermissionsService.instance
          .checkAll()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      snap = const AppCapabilitySnapshot(
        location: CapabilityStatus.unavailable,
        camera: CapabilityStatus.unavailable,
        notifications: CapabilityStatus.unavailable,
        sms: CapabilityStatus.unavailable,
        biometrics: CapabilityStatus.unavailable,
        biometricInfo: BiometricCapabilities(
          available: false,
          hasFace: false,
          hasFingerprint: false,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _snap = snap;
        _loading = false;
      });
    }
  }

  String _statusText(CapabilityStatus status) {
    switch (status) {
      case CapabilityStatus.granted:
        return widget.isAr ? 'مفعّلة' : 'Granted';
      case CapabilityStatus.denied:
        return widget.isAr ? 'تحتاج إذن' : 'Tap to Allow';
      case CapabilityStatus.permanentlyDenied:
        return widget.isAr ? 'مغلقة بالإعدادات' : 'Settings';
      case CapabilityStatus.unavailable:
        return widget.isAr ? 'غير متاحة' : 'Unavailable';
    }
  }

  Color _statusColor(ColorScheme cs, CapabilityStatus status) {
    switch (status) {
      case CapabilityStatus.granted:
        return Colors.green.shade700;
      case CapabilityStatus.denied:
        return cs.primary;
      case CapabilityStatus.permanentlyDenied:
        return cs.error;
      case CapabilityStatus.unavailable:
        return cs.onSurfaceVariant;
    }
  }

  Widget _permRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required CapabilityStatus status,
    Future<CapabilityStatus> Function()? onRequest,
  }) {
    final cs = Theme.of(context).colorScheme;
    final col = _statusColor(cs, status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: col.withValues(alpha: 0.12),
          child: Icon(icon, color: col, size: 20),
        ),
        title: Text(title, style: AppTypography.labelLg),
        subtitle: Text(subtitle, style: AppTypography.labelSm),
        trailing: status == CapabilityStatus.granted
            ? Chip(
                label: Text(_statusText(status),
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.green.withValues(alpha: 0.14),
                side: BorderSide.none,
              )
            : TextButton(
                onPressed: onRequest == null
                    ? null
                    : () async {
                        if (status == CapabilityStatus.permanentlyDenied) {
                          await AppPermissionsService.instance
                              .openDeviceSettings();
                        } else {
                          await onRequest();
                        }
                        await _refresh();
                      },
                child: Text(_statusText(status)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = widget.isAr;
    final snap = _snap;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Container(
            key: const Key('permissions-sheet-card'),
            decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: SafeArea(
            top: false,
            child: _loading || snap == null
                ? const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isAr
                          ? 'صلاحيات التطبيق الضرورية فقط (5 صلاحيات)'
                          : 'Least-Privilege App Permissions (5 Only)',
                      style: AppTypography.headlineMd,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? 'التطبيق لا يطلب أي صلاحيات غير مستخدمة (تمت إزالة NFC والاتصال المباشر).'
                          : 'MNIS requests strictly the 5 permissions actually used in the app.',
                      style: AppTypography.bodySm
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    _permRow(
                      icon: Icons.location_on_outlined,
                      title: isAr ? 'الموقع الجغرافي (GPS)' : 'Live Location',
                      subtitle: isAr
                          ? 'لإظهار الأطباء والمعامل في محافظتك الحالية فقط'
                          : 'Match doctors & labs to your current governorate',
                      status: snap.location,
                      onRequest: AppPermissionsService.instance.requestLocation,
                    ),
                    _permRow(
                      icon: Icons.camera_alt_outlined,
                      title: isAr ? 'الكاميرا' : 'Camera',
                      subtitle: isAr
                          ? 'لتصوير التحاليل والروشتات ورفعها بملفك الصحي'
                          : 'Capture lab reports & documents directly',
                      status: snap.camera,
                      onRequest: AppPermissionsService.instance.requestCamera,
                    ),
                    _permRow(
                      icon: Icons.notifications_active_outlined,
                      title: isAr ? 'الإشعارات' : 'Notifications',
                      subtitle: isAr
                          ? 'لتنبيهات مواعيد الأدوية والمواعيد والنتائج'
                          : 'Medication dose reminders & clinical alerts',
                      status: snap.notifications,
                      onRequest:
                          AppPermissionsService.instance.requestNotifications,
                    ),
                    _permRow(
                      icon: Icons.sms_outlined,
                      title: isAr ? 'الرسائل النصية (SMS)' : 'SMS Verification',
                      subtitle: isAr
                          ? 'للتعبئة التلقائية الآمنة لرسائل كود التحقق SMS داخل التطبيق'
                          : 'Secure in-app autofill for real SMS verification codes',
                      status: snap.sms,
                      onRequest: AppPermissionsService.instance.requestSms,
                    ),
                    _permRow(
                      icon: snap.biometricInfo.hasFace
                          ? Icons.face_rounded
                          : Icons.fingerprint_rounded,
                      title: snap.biometricInfo.label(isAr),
                      subtitle: isAr
                          ? 'لحماية السجل الطبي وفتح التطبيق بالبصمة أو الوجه'
                          : 'Hardware fingerprint & face unlock security',
                      status: snap.biometrics,
                    ),
                  ],
                ),
              ),
          ),
        ),
      ),
      ),
    );
  }
}

void _showAiAssistantDialog(BuildContext context, {required bool isAr}) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: _AiAssistantDialog(isAr: isAr),
    ),
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


