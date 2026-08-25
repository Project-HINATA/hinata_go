import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/navigation/router.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/ui/pages/remote/remote_page.dart';
import 'package:hinata_go/ui/pages/saved_cards_page.dart';
import 'package:hinata_go/ui/pages/scan_page.dart';
import 'package:hinata_go/ui/pages/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget createTestApp({
  required SharedPreferences preferences,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    child: Consumer(
      builder: (context, ref, child) {
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  group('4-Tab Navigation & Routing Tests', () {
    testWidgets('renders all 4 navigation destinations in mobile bottom bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp(preferences: preferences));
      await tester.pumpAndSettle();

      // Check bottom NavigationBar exists
      expect(find.byType(NavigationBar), findsOneWidget);

      // Verify all 4 tab labels are present
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Verify initial route is ScanPage
      expect(find.byType(ScanPage), findsOneWidget);
    });

    testWidgets('tapping each tab switches branches correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp(preferences: preferences));
      await tester.pumpAndSettle();

      // Tap Cards Tab (Index 1)
      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedCardsPage), findsOneWidget);

      // Tap Remote Tab (Index 2)
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);

      // Tap Settings Tab (Index 3)
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      // Tap Scan Tab (Index 0)
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanPage), findsOneWidget);
    });

    testWidgets('renders all 4 navigation destinations in rail mode (desktop/landscape)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp(preferences: preferences));
      await tester.pumpAndSettle();

      // In wide view, NavigationRail should be used instead of NavigationBar
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Check 4 destinations in NavigationRail
      final navRail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(navRail.destinations.length, 4);

      // Tap Remote tab on rail
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);
    });

    testWidgets('Chinese localization displays translated tab labels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(preferences: preferences, locale: const Locale('zh')),
      );
      await tester.pumpAndSettle();

      expect(find.text('扫描'), findsOneWidget);
      expect(find.text('卡片'), findsOneWidget);
      expect(find.text('远程'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('swipe gesture navigates between all 4 tabs', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp(preferences: preferences));
      await tester.pumpAndSettle();

      // Initially at Scan (0)
      expect(find.byType(ScanPage), findsOneWidget);

      // Swipe left: 0 -> 1 (Cards)
      await tester.fling(find.byType(ScanPage), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(SavedCardsPage), findsOneWidget);

      // On SavedCardsPage, first swipe left switches from favorites folder to history folder
      await tester.fling(find.byType(SavedCardsPage), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(SavedCardsPage), findsOneWidget);

      // Second swipe left on last folder switches tab: 1 -> 2 (Remote)
      await tester.fling(find.byType(SavedCardsPage), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);

      // Swipe left: 2 -> 3 (Settings)
      await tester.fling(find.byType(RemotePage), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      // Swipe left at index 3 -> stays at 3
      await tester.fling(find.byType(SettingsPage), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      // Swipe right: 3 -> 2 (Remote)
      await tester.fling(find.byType(SettingsPage), const Offset(500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);
    });
  });
}
