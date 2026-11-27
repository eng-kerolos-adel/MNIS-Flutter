import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase/firebase_bootstrap.dart';
import 'core/l10n/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/providers.dart';
import 'core/models/models.dart';
import 'core/providers/app_lock_provider.dart';
import 'core/providers/session_provider.dart';
import 'core/storage/secure_session_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();

  if (!kIsWeb) {
    // Lock to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const ProviderScope(child: MnisApp()));
}

/// Determines whether returning from background should display the biometric
/// app-lock screen. Transient OS permission/overlay pauses and active onboarding,
/// authentication, password-change, or SMS verification routes are never
/// interrupted so OTP confirmation state is preserved safely.
bool shouldLockOnResume({
  required String currentPath,
  required bool biometricEnabled,
  required SessionUser? user,
  required Duration backgroundDuration,
}) {
  if (!biometricEnabled || user == null) return false;
  if (backgroundDuration < const Duration(seconds: 3)) return false;
  if (user.mustChangePassword || user.requiresPhoneVerification) return false;
  const protectedRoutes = {
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.login,
    AppRoutes.changePassword,
    AppRoutes.verifyPhone,
    AppRoutes.appLock,
  };
  return !protectedRoutes.contains(currentPath);
}

class MnisApp extends ConsumerStatefulWidget {
  const MnisApp({super.key});

  @override
  ConsumerState<MnisApp> createState() => _MnisAppState();
}

class _MnisAppState extends ConsumerState<MnisApp> with WidgetsBindingObserver {
  AppLifecycleState? _lastState;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock only when genuinely returning from background on an unlocked,
    // fully verified screen — never mid-verification or on brief OS overlays.
    final wasBackgrounded = _lastState == AppLifecycleState.paused;
    _lastState = state;
    if (state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed || !wasBackgrounded) return;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final bgDuration = pausedAt == null
        ? Duration.zero
        : DateTime.now().difference(pausedAt);

    SecureSessionStore.instance.readBiometricEnabled().then((enabled) {
      if (!mounted) return;
      final router = ref.read(routerProvider);
      final currentPath =
          router.routerDelegate.currentConfiguration.uri.path;
      final user = ref.read(sessionControllerProvider).value;
      if (!shouldLockOnResume(
        currentPath: currentPath,
        biometricEnabled: enabled,
        user: user,
        backgroundDuration: bgDuration,
      )) {
        return;
      }
      ref.read(appUnlockedProvider.notifier).state = false;
      router.go(AppRoutes.appLock);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'MNIS — منظومة الهوية الطبية الوطنية',
      debugShowCheckedModeBanner: false,

      // Theming
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // Localizations
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Router
      routerConfig: router,
    );
  }
}


