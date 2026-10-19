import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../core/app_host_mode.dart';
import '../models/card/card.dart';
import '../models/card/saved_card.dart';
import '../providers/navigation_bar_provider.dart';
import '../ui/adaptive_tab_shell.dart';
import '../ui/native_hosted_scaffold.dart';
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
import '../ui/shell_state_sync.dart';
import '../ui/widgets/animated_branch_container.dart';
import '../ui/widgets/app_scaffold.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final routerProvider = Provider<GoRouter>((ref) {
  final hostMode = ref.watch(appHostModeProvider);
  final usesNativeShell = hostMode == AppHostMode.nativeIOS;
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/scan',
    observers: usesNativeShell
        ? [ref.watch(nativeShellNavigatorObserverProvider)]
        : null,
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
          final extra = state.extra;
          if (extra is SavedCard) {
            return CardDetailPage(savedCard: extra);
          } else if (extra is ICCard) {
            return CardDetailPage(card: extra);
          }
          throw ArgumentError('Invalid extra for /card_detail: $extra');
        },
      ),
      GoRoute(
        path: '/instances',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const InstancesPage(),
      ),
      GoRoute(
        path: '/scan_logs',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ScanLogsPage(),
      ),
      StatefulShellRoute(
        // Branch navigators must not forward their events to the root
        // observer: the native shell tracks the root navigator's stack.
        notifyRootObserver: false,
        navigatorContainerBuilder: (context, navigationShell, children) {
          return Consumer(
            builder: (context, ref, _) => AnimatedBranchContainer(
              currentIndex: navigationShell.currentIndex,
              axis: ref.watch(navigationBarAxisProvider),
              children: children,
            ),
          );
        },
        builder: (context, state, navigationShell) {
          if (usesNativeShell) {
            return NativeHostedScaffold(navigationShell: navigationShell);
          }
          return useCupertinoChrome
              ? AdaptiveTabShell(navigationShell: navigationShell)
              : ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scan',
                builder: (context, state) => const ScanPage(),
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
