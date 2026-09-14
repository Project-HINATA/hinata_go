import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/core/app_host_mode.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/navigation_provider.dart';
import 'package:hinata_go/ui/app_action_button.dart';
import 'package:hinata_go/ui/shell_state_sync.dart';
import 'package:hinata_go/ui/widgets/animated_branch_container.dart';

/// Mirrors the private channel used by the native shell bridge.
const _nativeShellChannel = MethodChannel('dev.hinata.go/native_shell');

class _MockAppUpdateNotifier extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}

class _ShellBody extends ConsumerWidget {
  const _ShellBody({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: navigationShell);
  }
}

class _CardsPage extends HookConsumerWidget {
  const _CardsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: const SizedBox(),
      floatingActionButton: buildAppActionButton(
        context,
        ref,
        config: const AppActionConfig(
          id: 'cardsAction',
          icon: Icons.add,
          tooltip: 'Add',
          nativeSymbol: 'plus',
        ),
      ),
    );
  }
}

/// Stands in for a root-level page such as `/instances`, which owns an action button of its own.
class _RootActionPage extends HookConsumerWidget {
  const _RootActionPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: const SizedBox(),
      floatingActionButton: buildAppActionButton(
        context,
        ref,
        config: const AppActionConfig(
          id: 'rootAction',
          icon: Icons.add,
          tooltip: 'Add',
          nativeSymbol: 'plus',
        ),
      ),
    );
  }
}

class _PlainPage extends StatelessWidget {
  const _PlainPage();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StatefulNavigationShell shell;
  late ProviderContainer container;
  late GoRouter router;
  late List<Map<String, Object?>> chromeCalls;

  setUp(() {
    chromeCalls = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeShellChannel, (call) async {
          if (call.method == 'setChromeVisibility') {
            chromeCalls.add(Map<String, Object?>.from(call.arguments as Map));
          }
          return null;
        });

    container = ProviderContainer(
      overrides: [
        appHostModeProvider.overrideWithValue(AppHostMode.nativeIOS),
        appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
      ],
    );

    router = GoRouter(
      initialLocation: '/scan',
      observers: [container.read(nativeShellNavigatorObserverProvider)],
      routes: [
        StatefulShellRoute(
          notifyRootObserver: false,
          navigatorContainerBuilder: (context, navigationShell, children) =>
              AnimatedBranchContainer(
                currentIndex: navigationShell.currentIndex,
                children: children,
              ),
          builder: (context, state, navigationShell) {
            shell = navigationShell;
            return _ShellBody(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/scan',
                  builder: (context, state) => const _PlainPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/cards',
                  builder: (context, state) => const _CardsPage(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => const _PlainPage(),
        ),
        GoRoute(
          path: '/root_action',
          builder: (context, state) => const _RootActionPage(),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeShellChannel, null);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presents a dialog the way the app does: on the root navigator, above everything else.
  Future<void> openDialog(WidgetTester tester) async {
    final context = router.routerDelegate.navigatorKey.currentContext!;
    unawaited(
      showDialog<void>(context: context, builder: (_) => const SizedBox()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeDialog(WidgetTester tester) async {
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  }

  testWidgets('off-screen branches never own the action button', (
    tester,
  ) async {
    await pumpApp(tester);

    // /scan is selected, so the mounted `/cards` branch must not publish anything.
    expect(container.read(appActionNotifierProvider), isNull);

    shell.goBranch(1);
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');

    shell.goBranch(0);
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider), isNull);
  });

  testWidgets('a root-level route clears the branch action button', (
    tester,
  ) async {
    await pumpApp(tester);

    shell.goBranch(1);
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');

    router.push('/detail');
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider), isNull);
    expect(chromeCalls.last['tabBarVisible'], isFalse);

    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');
    expect(chromeCalls.last['tabBarVisible'], isTrue);
  });

  testWidgets('a dialog keeps the branch action button on screen', (
    tester,
  ) async {
    await pumpApp(tester);

    shell.goBranch(1);
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');

    await openDialog(tester);

    // The button stays put while the dialog is up, and the chrome is only dimmed — popping it out
    // here is what used to cut the presentation animation short.
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');
    expect(chromeCalls.last['tabBarVisible'], isTrue);
    expect(chromeCalls.last['dimmed'], isTrue);

    await closeDialog(tester);
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');
    expect(chromeCalls.last['dimmed'], isFalse);
  });

  testWidgets('a dialog over a root-level page keeps the tab bar hidden', (
    tester,
  ) async {
    await pumpApp(tester);

    router.push('/root_action');
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'rootAction');
    expect(chromeCalls.last['tabBarVisible'], isFalse);

    await openDialog(tester);

    // The dialog sits on top of an opaque root-level route, so the shell is still replaced and the
    // tab bar must stay hidden …
    expect(chromeCalls.last['tabBarVisible'], isFalse);
    expect(chromeCalls.last['dimmed'], isTrue);
    // … while the page below keeps owning the button.
    expect(container.read(appActionNotifierProvider)?.id, 'rootAction');

    await closeDialog(tester);
    expect(chromeCalls.last['tabBarVisible'], isFalse);
    expect(container.read(appActionNotifierProvider)?.id, 'rootAction');

    router.pop();
    await tester.pumpAndSettle();
    expect(chromeCalls.last['tabBarVisible'], isTrue);
  });
}
