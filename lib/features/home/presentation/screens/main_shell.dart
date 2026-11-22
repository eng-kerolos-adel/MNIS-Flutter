import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/firebase/firebase_messaging_service.dart';
import '../../../../core/firebase/firebase_remote_config_service.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/biometric_enrollment.dart';
import '../../../../core/utils/providers.dart';
import '../../../../core/providers/notifications_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/models/models.dart';
import '../../../../core/router/app_router.dart';

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const MainShell({super.key, required this.shell});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<String>? _routeSub;
  bool _checkedBiometricPrompt = false;

  @override
  void initState() {
    super.initState();
    _fgSub = FirebaseMessagingService.instance.onForegroundMessage.listen((msg) {
      ref.invalidate(notificationsProvider);
      if (!mounted) return;
      final isAr = ref.read(localeProvider).languageCode == 'ar';
      final title = isAr
          ? ((msg.data['titleAr'] as String?) ?? msg.notification?.title ?? 'إشعار جديد')
          : ((msg.data['titleEn'] as String?) ?? msg.notification?.title ?? 'New Alert');
      final body = isAr
          ? ((msg.data['bodyAr'] as String?) ?? msg.notification?.body ?? '')
          : ((msg.data['bodyEn'] as String?) ?? msg.notification?.body ?? '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(body.isNotEmpty ? '$title — $body' : title),
          action: SnackBarAction(
            label: isAr ? 'عرض' : 'View',
            onPressed: () {
              if (mounted) context.push(AppRoutes.notifications);
            },
          ),
        ),
      );
    });

    _routeSub = FirebaseMessagingService.instance.onNavigateRoute.listen((route) {
      if (mounted) context.push(route);
    });
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    _routeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Enforce mandatory security & SMS verification gates on every shell build.
    final currentUser = ref.watch(sessionControllerProvider).value;
    if (currentUser != null && currentUser.mustChangePassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.changePassword);
      });
      return const SizedBox.shrink();
    }
    if (currentUser != null && currentUser.requiresPhoneVerification) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.verifyPhone);
      });
      return const SizedBox.shrink();
    }
    if (currentUser != null && !_checkedBiometricPrompt) {
      _checkedBiometricPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          unawaited(
            promptBiometricEnrollmentIfEligible(context, ref, currentUser.id),
          );
        }
      });
    }

    // A refresh failure anywhere in the app (expired/stolen session) clears
    // sessionControllerProvider; bounce straight back to the login screen.
    ref.listen<AsyncValue<SessionUser?>>(sessionControllerProvider, (prev, next) {
      final wasSignedIn = prev?.value != null;
      final signedOutNow = !next.isLoading && next.value == null;
      if (wasSignedIn && signedOutNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(AppRoutes.login);
        });
      }
    });
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final rc = FirebaseRemoteConfigService.instance;

    final navItems = [
      (icon: Icons.home_rounded, label: l.navHome),
      (icon: Icons.folder_shared_rounded, label: l.navMedical),
      (icon: Icons.biotech_rounded, label: l.navLab),
      (icon: Icons.medication_rounded, label: l.navRx),
      (icon: Icons.qr_code_2_rounded, label: l.navQr),
    ];

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Column(
          children: [
            if (rc.maintenanceMode)
              SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr ? rc.maintenanceMessageAr : rc.maintenanceMessageEn,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: widget.shell),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceContainerLowDark
                : AppColors.surfaceContainerLowest,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                children: List.generate(navItems.length, (i) {
                  final selected = widget.shell.currentIndex == i;
                  final item = navItems[i];
                  return Expanded(
                    child: InkWell(
                      onTap: () => widget.shell.goBranch(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon with indicator
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: selected
                                    ? cs.primaryContainer.withOpacity(0.35)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item.icon,
                                size: 24,
                                color: selected
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: selected
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


