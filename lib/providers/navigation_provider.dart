import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../l10n/l10n.dart';
import 'app_update_provider.dart';

class NavigationTab {
  final int index;
  final String route;
  final String label;
  final IconData icon;

  /// SF Symbol shown by the native iOS 26+ tab bar.
  final String iosSymbol;

  /// Icon shown by the Cupertino tab bar before iOS 26.
  final IconData cupertinoIcon;
  final bool hasBadge;

  const NavigationTab({
    required this.index,
    required this.route,
    required this.label,
    required this.icon,
    required this.iosSymbol,
    required this.cupertinoIcon,
    this.hasBadge = false,
  });
}

final navigationTabsProvider = Provider<List<NavigationTab>>((ref) {
  final hasUpdate = ref.watch(appUpdateProvider).hasUpdate;
  return [
    NavigationTab(
      index: 0,
      route: '/scan',
      label: l10n.scan,
      icon: Icons.nfc,
      iosSymbol: 'wave.3.right',
      cupertinoIcon: CupertinoIcons.dot_radiowaves_right,
    ),
    NavigationTab(
      index: 1,
      route: '/cards',
      label: l10n.cards,
      icon: Icons.credit_card,
      iosSymbol: 'creditcard',
      cupertinoIcon: CupertinoIcons.creditcard,
    ),
    NavigationTab(
      index: 2,
      route: '/settings',
      label: l10n.settings,
      icon: Icons.settings,
      iosSymbol: 'gearshape',
      cupertinoIcon: CupertinoIcons.gear,
      hasBadge: hasUpdate,
    ),
  ];
});

class AppActionItem {
  final String id;
  final String label;
  final IconData? icon;

  /// SF Symbol for the item in the native iOS menu.
  final String? nativeSymbol;
  final VoidCallback onPressed;

  const AppActionItem({
    required this.id,
    required this.label,
    this.icon,
    this.nativeSymbol,
    required this.onPressed,
  });
}

class AppActionConfig {
  final String id;
  final IconData icon;
  final String? label;
  final String tooltip;
  final String? nativeSymbol;
  final VoidCallback? onPressed;
  final List<AppActionItem>? menuItems;
  final bool visible;

  const AppActionConfig({
    required this.id,
    required this.icon,
    this.label,
    required this.tooltip,
    this.nativeSymbol,
    this.onPressed,
    this.menuItems,
    this.visible = true,
  });
}
