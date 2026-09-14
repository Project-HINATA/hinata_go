import 'package:flutter/material.dart';
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

class _MockAppUpdateNotifier extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}

class _ShellBody extends ConsumerWidget {
  const _ShellBody({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    syncShellState(context, ref, navigationShell.currentIndex);
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

class _PlainPage extends StatelessWidget {
  const _PlainPage();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

void main() {
  late StatefulNavigationShell shell;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/scan',
      routes: [
        StatefulShellRoute(
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
      ],
    );
    container = ProviderContainer(
      overrides: [
        appHostModeProvider.overrideWithValue(AppHostMode.nativeIOS),
        appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier()),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    container.dispose();
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

    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(appActionNotifierProvider)?.id, 'cardsAction');
  });
}
