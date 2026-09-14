import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../l10n/l10n.dart';
import 'app_update_provider.dart';

class NavigationTab {
  final int index;
  final String route;
  final String label;
  final IconData icon;
  final String iosSymbol;
  final bool hasBadge;

  const NavigationTab({
    required this.index,
    required this.route,
    required this.label,
    required this.icon,
    required this.iosSymbol,
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
    ),
    NavigationTab(
      index: 1,
      route: '/cards',
      label: l10n.cards,
      icon: Icons.credit_card,
      iosSymbol: 'creditcard',
    ),
    NavigationTab(
      index: 2,
      route: '/settings',
      label: l10n.settings,
      icon: Icons.settings,
      iosSymbol: 'gearshape',
      hasBadge: hasUpdate,
    ),
  ];
});

class AppActionItem {
  final String id;
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  const AppActionItem({
    required this.id,
    required this.label,
    this.icon,
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

final appActionNotifierProvider =
    NotifierProvider<AppActionNotifier, AppActionConfig?>(() {
      return AppActionNotifier();
    });

class AppActionNotifier extends Notifier<AppActionConfig?> {
  @override
  AppActionConfig? build() => null;

  void setConfig(AppActionConfig config) {
    state = config;
  }

  void clear() {
    if (state != null) {
      state = null;
    }
  }

  void execute(String actionId) {
    final current = state;
    if (current == null) return;
    if (current.id == actionId) {
      current.onPressed?.call();
      return;
    }
    if (current.menuItems != null) {
      for (final item in current.menuItems!) {
        if (item.id == actionId) {
          item.onPressed();
          return;
        }
      }
    }
  }
}

enum NativeShellAction { addFolder, addCard }

final nativeShellActionProvider =
    NotifierProvider<NativeShellActionNotifier, NativeShellAction?>(() {
      return NativeShellActionNotifier();
    });

class NativeShellActionNotifier extends Notifier<NativeShellAction?> {
  @override
  NativeShellAction? build() => null;

  void trigger(NativeShellAction action) => state = action;

  void clear() => state = null;
}

/// Provider to track the current active branch index in the main scaffold.
/// 0: Reader, 1: Cards, 2: Settings
final activeBranchProvider = NotifierProvider<ActiveBranchNotifier, int>(() {
  return ActiveBranchNotifier();
});

class ActiveBranchNotifier extends Notifier<int> {
  @override
  int build() {
    return 0;
  }

  void setIndex(int index) {
    state = index;
  }
}

/// Provider to track if the main scaffold is currently covered by a root-level route (like a dialog or CardDetail).
final isScaffoldCoveredProvider =
    NotifierProvider<ScaffoldCoveredNotifier, bool>(() {
      return ScaffoldCoveredNotifier();
    });

class ScaffoldCoveredNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setCovered(bool covered) {
    state = covered;
  }
}
