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

/// The claim one page holds on the native action button while it is on screen.
class _ActionClaim {
  const _ActionClaim({required this.config, required this.inShell});

  final AppActionConfig config;

  /// The page lives inside the shell. A page outside it — a root-level route such as `/instances` —
  /// outranks it, because a root-level route covers the shell when it is the one being shown.
  final bool inShell;
}

class AppActionNotifier extends Notifier<AppActionConfig?> {
  final Map<Object, _ActionClaim> _claims = <Object, _ActionClaim>{};

  @override
  AppActionConfig? build() {
    _claims.clear();
    return null;
  }

  /// Publishes what the page behind [owner] wants the native button to show.
  ///
  /// Pages leave and arrive in an order the framework does not promise: when a route pops, the page
  /// being removed can report itself after the page below it has already claimed the button. Claims
  /// are therefore collected per owner rather than written over each other, and the button is
  /// resolved from what is left on screen, so a page that goes away can only withdraw its own claim.
  void claim(
    Object owner, {
    required bool onScreen,
    required bool inShell,
    AppActionConfig? config,
  }) {
    if (!onScreen || config == null) {
      _claims.remove(owner);
    } else {
      _claims[owner] = _ActionClaim(config: config, inShell: inShell);
    }
    _resolve();
  }

  /// Drops the claim of a page that is going away for good.
  void release(Object owner) {
    if (_claims.remove(owner) != null) _resolve();
  }

  void _resolve() {
    _ActionClaim? winner;
    for (final claim in _claims.values) {
      if (winner == null || (winner.inShell && !claim.inShell)) {
        winner = claim;
      }
    }

    final next = winner?.config;
    if (!identical(next, state)) state = next;
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

/// What the native shell currently shows, derived from the root navigator's route stack.
///
/// The native tab bar belongs to the shell, which is the bottom-most route of the root navigator.
/// It stays on screen while that route is what the user sees — a dialog presented on top of it
/// only dims the chrome — and goes away as soon as an opaque route replaces it.
@immutable
class NativeShellCoverage {
  const NativeShellCoverage({
    this.visibleRoute,
    this.shellRoute,
    this.modalOnTop = false,
  });

  /// The top-most opaque route of the root navigator: what the user is actually looking at.
  final Route<dynamic>? visibleRoute;

  /// The bottom-most route of the root navigator, which hosts the shell.
  final Route<dynamic>? shellRoute;

  /// A modal route such as a dialog or bottom sheet sits above everything else.
  final bool modalOnTop;

  /// True when an opaque route replaces the shell, so its chrome does not belong on screen.
  bool get shellCovered =>
      visibleRoute != null &&
      shellRoute != null &&
      !identical(visibleRoute, shellRoute);
}

final nativeShellCoverageProvider =
    NotifierProvider<NativeShellCoverageNotifier, NativeShellCoverage>(() {
      return NativeShellCoverageNotifier();
    });

class NativeShellCoverageNotifier extends Notifier<NativeShellCoverage> {
  @override
  NativeShellCoverage build() => const NativeShellCoverage();

  void update(NativeShellCoverage coverage) {
    state = coverage;
  }
}
