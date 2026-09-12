import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../models/card/card.dart';
import '../models/card/saved_card.dart';
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
import 'package:hinata_go/features/prism/prism_machine_login_page.dart';
import 'package:hinata_go/features/prism/services/prism_invocation_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final routerProvider = Provider<GoRouter>((ref) {
  final invocationService = ref.watch(prismInvocationProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/scan',
    refreshListenable: invocationService,
    redirect: (context, state) {
      final shopCode = invocationService.pendingShopCode;
      final publicId = invocationService.pendingPublicId;
      if (shopCode == null || publicId == null) return null;
      final target =
          '/prism/${Uri.encodeComponent(shopCode)}/${Uri.encodeComponent(publicId)}?origin=${Uri.encodeComponent(invocationService.pendingOrigin!.origin)}';
      return state.uri.toString() == target ? null : target;
    },
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
      GoRoute(
        path: '/t/:shopCode/:publicId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PrismMachineLoginPage(
          origin: state.uri.hasAuthority
              ? Uri.parse(state.uri.origin)
              : (state.uri.queryParameters['origin'] == null
                    ? null
                    : Uri.parse(state.uri.queryParameters['origin']!)),
          key: ValueKey(
            '${state.uri.host}/${state.uri.query}/${state.pathParameters['shopCode']}/${state.pathParameters['publicId']}',
          ),
          shopCode: state.pathParameters['shopCode']!,
          publicId: state.pathParameters['publicId']!,
        ),
      ),
      GoRoute(
        path: '/prism/:shopCode/:publicId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PrismMachineLoginPage(
          origin: state.uri.hasAuthority
              ? Uri.parse(state.uri.origin)
              : (state.uri.queryParameters['origin'] == null
                    ? null
                    : Uri.parse(state.uri.queryParameters['origin']!)),
          key: ValueKey(
            '${state.uri.host}/${state.uri.query}/${state.pathParameters['shopCode']}/${state.pathParameters['publicId']}',
          ),
          shopCode: state.pathParameters['shopCode']!,
          publicId: state.pathParameters['publicId']!,
        ),
      ),
    ],
  );
});
