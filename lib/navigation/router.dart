import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/scaffold_with_navbar.dart';
import '../ui/pages/reader_page.dart';
import '../ui/pages/saved_cards_page.dart';
import '../ui/pages/settings_page.dart';
import '../ui/pages/instances_page.dart';
import '../ui/pages/scan_logs_page.dart';
import '../ui/widgets/animated_branch_container.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/reader',
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) {
          return AnimatedBranchContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reader',
                builder: (context, state) => const ReaderPage(),
              ),
              GoRoute(
                path: '/scan_logs',
                builder: (context, state) => const ScanLogsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cards',
                builder: (context, state) => const SavedCardsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
              GoRoute(
                path: '/instances',
                builder: (context, state) => const InstancesPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
