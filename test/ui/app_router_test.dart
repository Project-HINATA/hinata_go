import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/navigation/router.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the app's real router on the Material chrome that Android and web share.
class _MockAppUpdateNotifier extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    router = container.read(routerProvider);
  });

  tearDown(() => container.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AdaptiveToolbarHost(child: child!),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tabs switch between the top-level pages', (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('HINATA Go'), findsOneWidget);

    await tester.tap(find.text('Cards').last);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/cards');

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
  });

  testWidgets('each page shows its own floating action button', (tester) async {
    await pumpApp(tester);
    expect(find.byType(FloatingActionButton), findsNothing);

    router.go('/cards');
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final label in [
      l10n.addAimeBanapass,
      l10n.ndefCreate,
      l10n.newFolder,
    ]) {
      expect(find.widgetWithText(FloatingActionButton, label), findsOneWidget);
    }

    router.push('/instances');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FloatingActionButton, l10n.addInstance),
      findsOneWidget,
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FloatingActionButton, l10n.newFolder),
      findsOneWidget,
    );
  });

  testWidgets('the mobile NDEF editor opens and closes over the shell', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go('/cards');
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(
      find.widgetWithText(FloatingActionButton, l10n.ndefCreate),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byTooltip(l10n.cancel).last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
