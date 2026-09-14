import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/core/app_host_mode.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/navigation_provider.dart';
import 'package:hinata_go/ui/app_action_button.dart';

class _MockAppUpdateNotifier extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}

void main() {
  test('navigationTabsProvider provides 3 tabs with symbols', () {
    final container = ProviderContainer(
      overrides: [
        appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final tabs = container.read(navigationTabsProvider);
    expect(tabs.length, 3);
    expect(tabs[0].route, '/scan');
    expect(tabs[0].iosSymbol, 'wave.3.right');
    expect(tabs[1].route, '/cards');
    expect(tabs[1].iosSymbol, 'creditcard');
    expect(tabs[2].route, '/settings');
    expect(tabs[2].iosSymbol, 'gearshape');
  });

  testWidgets('buildAppActionButton renders FAB in flutterShell mode', (
    tester,
  ) async {
    bool tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appHostModeProvider.overrideWithValue(AppHostMode.flutterShell),
          appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            floatingActionButton: Consumer(
              builder: (context, ref, _) {
                return buildAppActionButton(
                  context,
                  ref,
                  config: AppActionConfig(
                    id: 'testAction',
                    icon: Icons.add,
                    label: 'Add',
                    tooltip: 'Add',
                    onPressed: () => tapped = true,
                  ),
                )!;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    expect(tapped, isTrue);
  });

  testWidgets('buildAppActionButton mounts registrar in nativeIOS mode', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appHostModeProvider.overrideWithValue(AppHostMode.nativeIOS),
        appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
      ],
    );
    addTearDown(container.dispose);

    bool tapped = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            floatingActionButton: Consumer(
              builder: (context, ref, _) {
                return buildAppActionButton(
                  context,
                  ref,
                  config: AppActionConfig(
                    id: 'testNative',
                    icon: Icons.add,
                    label: 'Native Add',
                    tooltip: 'Native Add',
                    onPressed: () => tapped = true,
                  ),
                )!;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // In native mode, Flutter tree does NOT display a FloatingActionButton
    expect(find.byType(FloatingActionButton), findsNothing);

    // The config is registered to appActionNotifierProvider
    final registered = container.read(appActionNotifierProvider);
    expect(registered, isNotNull);
    expect(registered?.id, 'testNative');

    // Executing the action from native triggers the callback
    container.read(appActionNotifierProvider.notifier).execute('testNative');
    expect(tapped, isTrue);
  });
}
