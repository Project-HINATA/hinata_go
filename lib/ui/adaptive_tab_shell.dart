import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/navigation_provider.dart';

/// Height of the content area of the iOS 26 Liquid Glass tab bar, above the
/// home indicator. UIKit insets a tab's safe area by this much.
const double _kNativeTabBarContentHeight = 49;

/// The iOS shell: the top-level pages under a native tab bar. On iOS 26+ it is
/// a Liquid Glass `UITabBar`, which moves into the vertical bar on iPhone Duo;
/// earlier iOS versions get a Cupertino tab bar.
class AdaptiveTabShell extends ConsumerWidget {
  const AdaptiveTabShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(navigationTabsProvider);
    final nativeTabBar = PlatformInfo.isIOS26OrHigher();

    return AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: nativeTabBar
          ? _NativeTabBarInset(child: navigationShell)
          : navigationShell,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onTap: _goBranch,
        items: [
          for (final tab in tabs)
            AdaptiveNavigationDestination(
              icon: nativeTabBar ? tab.iosSymbol : tab.cupertinoIcon,
              label: tab.label,
              badgeCount: tab.hasBadge ? 1 : null,
            ),
        ],
      ),
    );
  }
}

/// The native tab bar floats over the pages, so it does not shrink them. Grow
/// their bottom safe area by the bar instead, as UIKit does for a tab's content,
/// so lists scroll clear of it. On iPhone Duo the tabs sit in the vertical bar
/// and the bottom edge stays free.
///
/// Always builds the [MediaQuery], so a change of Duo pose does not move the
/// navigator in the element tree and rebuild every page.
class _NativeTabBarInset extends StatelessWidget {
  const _NativeTabBarInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabsInVerticalBar =
        ToolbarChromeScope.maybeOf(context)?.hostsDuoControls ?? false;
    final inset = tabsInVerticalBar ? 0.0 : _kNativeTabBarContentHeight;

    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(
          bottom: mediaQuery.padding.bottom + inset,
        ),
        viewPadding: mediaQuery.viewPadding.copyWith(
          bottom: mediaQuery.viewPadding.bottom + inset,
        ),
      ),
      child: child,
    );
  }
}
