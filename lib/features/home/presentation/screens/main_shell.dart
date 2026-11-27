import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/firebase/firebase_messaging_service.dart';
import '../../../../core/firebase/firebase_remote_config_service.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/services/medication_reminder_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/biometric_enrollment.dart';
import '../../../../core/utils/providers.dart';
import '../../../../core/providers/data_providers.dart';
import '../../../../core/providers/notifications_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/models/models.dart';
import '../../../../core/router/app_router.dart';

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  final List<Widget> children;
  const MainShell({
    super.key,
    required this.shell,
    required this.children,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<String>? _routeSub;
  bool _checkedBiometricPrompt = false;
  late final PageController _pageController;
  bool _programmaticJump = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.shell.currentIndex);
    unawaited(_syncMedicationReminders());
    _fgSub = FirebaseMessagingService.instance.onForegroundMessage.listen((msg) {
      ref.invalidate(notificationsProvider);
      if (msg.data['type'] == 'PRESCRIPTION_DISPENSED' ||
          msg.data['type'] == 'MEDICATION_REMINDER') {
        ref.invalidate(medicationRemindersProvider);
        unawaited(_syncMedicationReminders());
      }
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
              if (mounted) AppRoutes.navigate(context, AppRoutes.notifications);
            },
          ),
        ),
      );
    });

    _routeSub = FirebaseMessagingService.instance.onNavigateRoute.listen((route) {
      if (mounted) AppRoutes.navigate(context, route);
    });
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.shell.currentIndex;
    if (target != oldWidget.shell.currentIndex && _pageController.hasClients) {
      final currentPage = _pageController.page?.round() ?? target;
      if (currentPage != target) {
        _programmaticJump = true;
        _pageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _programmaticJump = false);
      }
    }
  }

  Future<void> _syncMedicationReminders() async {
    try {
      await MedicationReminderService.instance.initialize();
      final list = await ref.read(repositoryProvider).medicationReminders();
      final isAr = mounted ? ref.read(localeProvider).languageCode == 'ar' : true;
      await MedicationReminderService.instance
          .syncReminders(list, isAr: isAr);
    } catch (_) {}
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    _routeSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (widget.shell.currentIndex == index) {
      AppRoutes.scrollTabToTop(index);
      return;
    }
    HapticFeedback.selectionClick();
    widget.shell.goBranch(index);
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

    final hasAbnormalLabs = ref.watch(labResultsProvider).value
            ?.any((p) => p.hasAbnormal) ??
        false;
    final activeRemindersCount = ref.watch(medicationRemindersProvider).value
            ?.where((r) => r.isActive && r.daysRemaining > 0)
            .length ??
        0;

    final navItems = [
      (icon: Icons.home_rounded, label: l.navHome, badgeCount: 0, alertDot: false),
      (icon: Icons.folder_shared_rounded, label: l.navMedical, badgeCount: 0, alertDot: false),
      (icon: Icons.biotech_rounded, label: l.navLab, badgeCount: 0, alertDot: hasAbnormalLabs),
      (icon: Icons.medication_rounded, label: l.navRx, badgeCount: activeRemindersCount, alertDot: false),
      (icon: Icons.qr_code_2_rounded, label: l.navQr, badgeCount: 0, alertDot: false),
    ];

    return PopScope(
      canPop: widget.shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.shell.currentIndex != 0) {
          HapticFeedback.lightImpact();
          widget.shell.goBranch(0);
        }
      },
      child: Directionality(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAr
                                ? rc.maintenanceMessageAr
                                : rc.maintenanceMessageEn,
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
              Expanded(
                child: ScrollConfiguration(
                  behavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemCount: widget.children.length,
                    onPageChanged: (index) {
                      if (_programmaticJump) return;
                      if (index != widget.shell.currentIndex) {
                        HapticFeedback.selectionClick();
                        widget.shell.goBranch(index);
                      }
                    },
                    itemBuilder: (context, index) => _KeepAliveBranchPage(
                      key: ValueKey('mnis_tab_branch_$index'),
                      child: widget.children[index],
                    ),
                  ),
                ),
              ),
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
              child: Center(
                heightFactor: 1.0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SizedBox(
                height: 70,
                child: Column(
                  children: [
                    // Live sliding active tab indicator synced with PageController
                    SizedBox(
                      height: 3,
                      child: AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, _) {
                          final rawPage = _pageController.hasClients
                              ? (_pageController.page ??
                                  widget.shell.currentIndex.toDouble())
                              : widget.shell.currentIndex.toDouble();
                          final page = rawPage.clamp(
                              0.0, (navItems.length - 1).toDouble());
                          final alignX = (isAr ? -1.0 : 1.0) *
                              (-1.0 + (2.0 * page / (navItems.length - 1)));
                          return FractionallySizedBox(
                            widthFactor: 1 / navItems.length,
                            alignment: Alignment(alignX, 0),
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: List.generate(navItems.length, (i) {
                          final selected = widget.shell.currentIndex == i;
                          final item = navItems[i];
                          return Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _selectTab(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? cs.primaryContainer
                                                  .withOpacity(0.35)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Icon(
                                              item.icon,
                                              size: 23,
                                              color: selected
                                                  ? cs.primary
                                                  : cs.onSurfaceVariant,
                                            ),
                                            if (item.alertDot)
                                              Positioned(
                                                top: -2,
                                                right: -4,
                                                child: Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: cs.error,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: cs.surface,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            else if (item.badgeCount > 0)
                                              Positioned(
                                                top: -4,
                                                right: -8,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.secondary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            99),
                                                  ),
                                                  child: Text(
                                                    '${item.badgeCount}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? cs.primary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
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

class _KeepAliveBranchPage extends StatefulWidget {
  final Widget child;
  const _KeepAliveBranchPage({super.key, required this.child});

  @override
  State<_KeepAliveBranchPage> createState() => _KeepAliveBranchPageState();
}

class _KeepAliveBranchPageState extends State<_KeepAliveBranchPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}


