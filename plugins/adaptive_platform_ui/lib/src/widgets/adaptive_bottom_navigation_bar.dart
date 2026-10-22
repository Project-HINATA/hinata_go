import 'package:flutter/cupertino.dart';
import 'adaptive_scaffold.dart';

/// Configuration for an adaptive bottom navigation bar
///
/// This class holds the configuration for the bottom navigation bar in [AdaptiveScaffold].
/// The actual rendering is platform-specific:
/// - iOS: CupertinoTabBar (custom or auto-generated). A native Liquid Glass
///   tab bar belongs to a UITabBarController above Flutter, not to a page.
/// - Android: NavigationBar (custom or auto-generated)
///
/// You can provide custom bottom navigation bars using [cupertinoTabBar] or [bottomNavigationBar]:
/// - If [cupertinoTabBar] is provided: Uses custom CupertinoTabBar on iOS
/// - If [bottomNavigationBar] is provided: Uses custom NavigationBar/BottomNavigationBar on Android
/// - Otherwise: Builds bottom navigation bar from [items]
class AdaptiveBottomNavigationBar {
  /// Creates an adaptive bottom navigation bar configuration
  const AdaptiveBottomNavigationBar({
    this.items,
    this.selectedIndex,
    this.onTap,
    this.cupertinoTabBar,
    this.bottomNavigationBar,
    this.selectedItemColor,
    this.unselectedItemColor,
  });

  /// Navigation items for bottom navigation bar
  /// These will be used to build the platform-specific navigation items if custom
  /// bars are not provided.
  final List<AdaptiveNavigationDestination>? items;

  /// Currently selected item index
  /// If null, no item will be selected
  final int? selectedIndex;

  /// Called when a navigation item is tapped
  /// If null, navigation will not be interactive
  final ValueChanged<int>? onTap;

  /// Custom CupertinoTabBar for iOS
  ///
  /// When provided, it is used on iOS.
  ///
  /// If not provided, a tab bar will be auto-generated from [items].
  ///
  /// Ignored on Android platforms.
  final CupertinoTabBar? cupertinoTabBar;

  /// Custom NavigationBar or BottomNavigationBar for Android
  ///
  /// When provided, this custom navigation bar will be used instead of building one
  /// from [items].
  ///
  /// Ignored on iOS platforms.
  final Widget? bottomNavigationBar;

  /// Color for the selected navigation item
  ///
  /// When provided:
  /// - iOS (native/CupertinoTabBar): Sets activeColor
  /// - Android (NavigationBar): Sets indicatorColor
  ///
  /// If null, uses platform defaults.
  final Color? selectedItemColor;

  /// Color for unselected navigation items
  ///
  /// When provided:
  /// - iOS (native/CupertinoTabBar): Sets inactiveColor
  /// - Android (NavigationBar): Not directly supported, but can affect icon colors
  ///
  /// If null, uses platform defaults.
  final Color? unselectedItemColor;

  /// Creates a copy of this bottom navigation bar with the given fields replaced
  AdaptiveBottomNavigationBar copyWith({
    List<AdaptiveNavigationDestination>? items,
    int? selectedIndex,
    ValueChanged<int>? onTap,
    CupertinoTabBar? cupertinoTabBar,
    Widget? bottomNavigationBar,
    Color? selectedItemColor,
    Color? unselectedItemColor,
  }) {
    return AdaptiveBottomNavigationBar(
      items: items ?? this.items,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      onTap: onTap ?? this.onTap,
      cupertinoTabBar: cupertinoTabBar ?? this.cupertinoTabBar,
      bottomNavigationBar: bottomNavigationBar ?? this.bottomNavigationBar,
      selectedItemColor: selectedItemColor ?? this.selectedItemColor,
      unselectedItemColor: unselectedItemColor ?? this.unselectedItemColor,
    );
  }
}
