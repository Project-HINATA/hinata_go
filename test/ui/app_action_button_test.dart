import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

  testWidgets('buildAppActionButton renders a Material FAB', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          floatingActionButton: Builder(
            builder: (context) => buildAppActionButton(
              context,
              config: AppActionConfig(
                id: 'testAction',
                icon: Icons.add,
                label: 'Add',
                tooltip: 'Add',
                onPressed: () => tapped = true,
              ),
            )!,
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    expect(tapped, isTrue);
  });

  testWidgets('a menu item may also answer a long press', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          floatingActionButton: Builder(
            builder: (context) => buildAppActionButton(
              context,
              config: AppActionConfig(
                id: 'menu',
                icon: Icons.add,
                tooltip: 'Add',
                menuItems: [
                  AppActionItem(
                    id: 'card',
                    label: 'Add card',
                    onPressed: () => calls.add('card tap'),
                    onLongPress: () => calls.add('card long press'),
                  ),
                  AppActionItem(
                    id: 'folder',
                    label: 'New folder',
                    onPressed: () => calls.add('folder tap'),
                  ),
                ],
              ),
            )!,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add card'));
    await tester.longPress(find.text('Add card'));
    await tester.longPress(find.text('New folder'));
    await tester.pumpAndSettle();

    expect(calls, ['card tap', 'card long press']);
  });

  testWidgets('a hidden action builds no FAB', (tester) async {
    Widget? button;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            button = buildAppActionButton(
              context,
              config: const AppActionConfig(
                id: 'hidden',
                icon: Icons.add,
                tooltip: 'Hidden',
                visible: false,
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(button, isNull);
  });

  group('buildToolbarAction', () {
    test('turns a plain action into a toolbar item', () {
      var tapped = false;
      final action = buildToolbarAction(
        AppActionConfig(
          id: 'addInstance',
          icon: Icons.add,
          tooltip: 'Add instance',
          nativeSymbol: 'plus',
          onPressed: () => tapped = true,
        ),
      )!;

      expect(action.iosSymbol, 'plus');
      expect(action.label, 'Add instance');
      expect(action.hasMenu, isFalse);
      action.onPressed();
      expect(tapped, isTrue);
    });

    test('turns menu items into a native menu', () {
      final selected = <String>[];
      final action = buildToolbarAction(
        AppActionConfig(
          id: 'cardsAction',
          icon: Icons.add,
          tooltip: 'Add',
          menuItems: [
            AppActionItem(
              id: 'addCard',
              label: 'Card',
              nativeSymbol: 'creditcard',
              onPressed: () => selected.add('addCard'),
            ),
            AppActionItem(
              id: 'addFolder',
              label: 'Folder',
              onPressed: () => selected.add('addFolder'),
            ),
          ],
        ),
      )!;

      expect(action.hasMenu, isTrue);
      final items = action.menuItems!.cast<AdaptivePopupMenuItem<dynamic>>();
      expect(items.map((item) => item.label), ['Card', 'Folder']);
      expect(items.first.icon, 'creditcard');

      action.selectMenuItem(1);
      expect(selected, ['addFolder']);
    });

    test('a hidden action has no toolbar item', () {
      expect(
        buildToolbarAction(
          AppActionConfig(
            id: 'hidden',
            icon: Icons.add,
            tooltip: 'Hidden',
            visible: false,
            onPressed: () {},
          ),
        ),
        isNull,
      );
    });
  });
}
