import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../models/card/card.dart';
import '../ui/app_layout.dart';
import '../ui/pages/camera_page.dart';
import '../ui/pages/card_detail_page.dart';
import '../ui/pages/device_control_page.dart';
import '../ui/pages/firmware_update_page.dart';
import '../ui/pages/instances_page.dart';
import '../ui/pages/saved_cards_page.dart';
import '../ui/pages/scan_logs_page.dart';
import '../ui/pages/scan_page.dart';
import '../ui/pages/settings_page.dart';
import '../ui/scaffold_with_navbar.dart';
import '../ui/widgets/animated_branch_container.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/camera',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CameraPage(),
      ),
      GoRoute(
        path: '/card_detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final card = state.extra as ICCard;
          return CardDetailPage(card: card);
        },
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) {
          return AnimatedBranchContainer(
            currentIndex: navigationShell.currentIndex,
            axis: context.appLayout.useRailNavigation
                ? Axis.vertical
                : Axis.horizontal,
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
                path: '/scan',
                builder: (context, state) => const ScanPage(),
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
      // Standalone routes for Device Control (if opened via direct navigation or deep link)
      GoRoute(
        path: '/device_hub',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DeviceControlPage(),
        routes: [
          if (firmwareFeatureEnabled)
            GoRoute(
              path: 'firmware',
              parentNavigatorKey: rootNavigatorKey,
              pageBuilder: (context, state) => const MaterialPage(
                child: FirmwareUpdatePage(),
                fullscreenDialog: true,
              ),
            ),
        ],
      ),
    ],
  );
});
