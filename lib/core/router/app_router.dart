import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/home/presentation/screens/main_shell.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/medical_file/presentation/screens/medical_file_screen.dart';
import '../../features/lab_results/presentation/screens/lab_results_screen.dart';
import '../../features/prescriptions/presentation/screens/prescriptions_screen.dart';
import '../../features/emergency_qr/presentation/screens/emergency_qr_screen.dart';
import '../../features/auth/presentation/screens/change_password_screen.dart';
import '../../features/auth/presentation/screens/phone_verification_screen.dart';
import '../../features/appointments/presentation/screens/appointments_screen.dart';
import '../../features/share_record/presentation/screens/share_record_screen.dart';
import '../../features/app_lock/presentation/screens/app_lock_screen.dart';
import '../../features/documents/presentation/screens/documents_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';

abstract class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const home = '/home';
  static const medicalFile = '/medical-file';
  static const labResults = '/lab-results';
  static const prescriptions = '/prescriptions';
  static const emergencyQr = '/emergency-qr';
  static const qrTab = '/qr-tab';
  static const shell = '/shell';
  static const changePassword = '/change-password';
  static const appointments = '/appointments';
  static const shareRecord = '/share-record';
  static const appLock = '/app-lock';
  static const documents = '/documents';
  static const notifications = '/notifications';
  static const verifyPhone = '/verify-phone';

  static final List<ScrollController> _tabScrollControllers =
      List.generate(5, (_) => ScrollController());

  static ScrollController tabScrollController(int index) =>
      _tabScrollControllers[index.clamp(0, 4)];

  static void scrollTabToTop(int index) {
    final ctrl = tabScrollController(index);
    if (ctrl.hasClients && ctrl.offset > 0) {
      HapticFeedback.lightImpact();
      ctrl.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Unified navigation helper that eliminates stacked duplicate screens:
  /// - Works safely from any BuildContext (modal bottom sheets, root navigator,
  ///   dialogs, or shell branches) via [GoRouter.maybeOf] without ever throwing
  ///   `No GoRouterState found in context`.
  /// - Any primary shell tab (`home`, `medicalFile`, `labResults`,
  ///   `prescriptions`, `qrTab`, or `emergencyQr`) switches directly to that
  ///   bottom-navigation branch instead of pushing a duplicate screen on top.
  /// - Secondary detail routes push cleanly at most once.
  static void navigateWithRouter(GoRouter router, String route) {
    HapticFeedback.selectionClick();
    final target = route == emergencyQr ? qrTab : route;
    if (target == home ||
        target == medicalFile ||
        target == labResults ||
        target == prescriptions ||
        target == qrTab) {
      router.go(target);
      return;
    }
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    if (currentPath == target) return;
    router.push(target);
  }

  static void navigate(BuildContext context, String route) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    navigateWithRouter(router, route);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => _fadeTransition(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      // Emergency QR available without auth
      GoRoute(
        path: AppRoutes.emergencyQr,
        pageBuilder: (context, state) {
          final fromLogin =
              state.uri.queryParameters['fromLogin'] == 'true';
          return _slideTransition(
            key: state.pageKey,
            child: EmergencyQrScreen(fromLogin: fromLogin),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const ChangePasswordScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.appointments,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const AppointmentsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.appLock,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const AppLockScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.documents,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const DocumentsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const NotificationsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.verifyPhone,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const PhoneVerificationScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.shareRecord,
        pageBuilder: (context, state) => _slideTransition(
          key: state.pageKey,
          child: const ShareRecordScreen(),
        ),
      ),
      // Main shell with swipeable PageView + bottom navigation
      StatefulShellRoute(
        builder: (context, state, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) =>
            MainShell(shell: shell, children: children),
        branches: [
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: AppRoutes.medicalFile,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const MedicalFileScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: AppRoutes.labResults,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const LabResultsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: AppRoutes.prescriptions,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const PrescriptionsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: AppRoutes.qrTab,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const EmergencyQrScreen(fromLogin: false),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<void> _fadeTransition({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 400),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

CustomTransitionPage<void> _slideTransition({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}


