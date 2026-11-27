// Minimal smoke & regression tests for MNIS app routing and bottom-sheet layout.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mnis_app/core/l10n/app_localizations.dart';
import 'package:mnis_app/core/models/models.dart';
import 'package:mnis_app/core/providers/data_providers.dart';
import 'package:mnis_app/core/providers/session_provider.dart';
import 'package:mnis_app/core/router/app_router.dart';
import 'package:mnis_app/core/widgets/account_sheet.dart';
import 'package:mnis_app/main.dart';

class _TestSessionController extends SessionController {
  @override
  Future<SessionUser?> build() async => const SessionUser(
        id: 'test-user-1',
        email: 'citizen@mnis.gov.eg',
        role: 'PATIENT',
        fullNameEn: 'Test Citizen',
        fullNameAr: 'مواطن تجريبي',
        patientId: 'test-patient-1',
        mustChangePassword: false,
        phoneVerified: true,
      );
}

void main() {
  testWidgets('MnisApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MnisApp()));
    // The splash screen's session bootstrap makes a real network call, which
    // has no server to answer in a test environment — just let one frame
    // settle instead of pumpAndSettle (which would wait for a timeout).
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(MaterialApp).evaluate().isNotEmpty ||
          find.byType(WidgetsApp).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets(
      'AppRoutes.navigate safely handles root navigator and bottom sheet contexts',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    builder: (sheetCtx) => Builder(
                      builder: (innerCtx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              final r = GoRouter.maybeOf(innerCtx);
                              Navigator.of(innerCtx, rootNavigator: true).pop();
                              if (r != null) {
                                AppRoutes.navigateWithRouter(
                                    r, AppRoutes.appointments);
                              }
                            },
                            child: const Text('GoAppts'),
                          ),
                          TextButton(
                            onPressed: () {
                              final host =
                                  Navigator.of(innerCtx, rootNavigator: true)
                                      .context;
                              AppRoutes.navigate(host, AppRoutes.medicalFile);
                            },
                            child: const Text('GoMedFile'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('OpenSheet'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.appointments,
          builder: (_, __) => const Scaffold(body: Text('AppointmentsPage')),
        ),
        GoRoute(
          path: AppRoutes.medicalFile,
          builder: (_, __) => const Scaffold(body: Text('MedicalFilePage')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenSheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GoAppts'));
    await tester.pumpAndSettle();
    expect(find.text('AppointmentsPage'), findsOneWidget);

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenSheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GoMedFile'));
    await tester.pumpAndSettle();
    expect(find.text('MedicalFilePage'), findsOneWidget);
  });

  testWidgets('showAccountSheet opens anchored at the bottom of the screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, _) => Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAccountSheet(ctx, ref),
                  child: const Text('OpenAccountSheet'),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileProvider.overrideWith(
            (ref) async => PatientProfile(
              mti: 'MTI-EG-123456',
              nationalId: '29901010101234',
              fullName: const Bilingual('Test Citizen', 'مواطن تجريبي'),
              sex: 'MALE',
              birthDate: DateTime(1999, 1, 1),
              bloodType: 'O+',
              phone: '+201000000000',
              phoneMasked: '+2010••••0000',
              phoneVerifiedAt: DateTime(2026, 1, 1),
              address: const Bilingual('Cairo', 'القاهرة'),
              photoUrl: null,
              insuranceActive: true,
              organDonor: false,
              chronicConditions: const [],
              allergies: const [],
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAccountSheet'));
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const Key('account-sheet-card'));
    expect(cardFinder, findsOneWidget);
    final rect = tester.getRect(cardFinder);
    // Card must sit near the bottom edge (915px), NOT pinned near y = 0 at top.
    expect(rect.bottom, greaterThan(850));
    expect(rect.top, greaterThan(150));
  });

  test('shouldLockOnResume never locks during SMS verification or brief overlays',
      () {
    const verifiedUser = SessionUser(
      id: 'u1',
      email: null,
      role: 'PATIENT',
      fullNameEn: 'Citizen',
      fullNameAr: 'مواطن',
      patientId: 'p1',
      mustChangePassword: false,
      phoneVerified: true,
    );
    const unverifiedUser = SessionUser(
      id: 'u2',
      email: null,
      role: 'PATIENT',
      fullNameEn: 'New Citizen',
      fullNameAr: 'مواطن جديد',
      patientId: 'p2',
      mustChangePassword: false,
      phoneVerified: false,
    );

    expect(
      shouldLockOnResume(
        currentPath: AppRoutes.verifyPhone,
        biometricEnabled: true,
        user: unverifiedUser,
        backgroundDuration: const Duration(seconds: 20),
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        currentPath: AppRoutes.verifyPhone,
        biometricEnabled: true,
        user: verifiedUser,
        backgroundDuration: const Duration(seconds: 20),
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        currentPath: AppRoutes.home,
        biometricEnabled: true,
        user: verifiedUser,
        backgroundDuration: const Duration(seconds: 1),
      ),
      isFalse,
    );
    expect(
      shouldLockOnResume(
        currentPath: AppRoutes.home,
        biometricEnabled: true,
        user: verifiedUser,
        backgroundDuration: const Duration(seconds: 10),
      ),
      isTrue,
    );
  });
}
