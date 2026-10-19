import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/providers/navigation_bar_provider.dart';
import 'package:hinata_go/ui/app_layout.dart';
import 'package:hinata_go/ui/widgets/app_scaffold.dart';

/// Resolves the navigation bar axis from the current layout and platform
/// chrome, then publishes it to [navigationBarAxisProvider].
///
/// It must sit below `AdaptiveToolbarHost`, because the Duo pose comes from
/// the toolbar host's `ToolbarChromeScope`. Riverpod forbids modifying a
/// provider during a widget lifecycle, so the value is published once the
/// frame completes; consumers see it from the next frame on.
class NavigationBarAxisScope extends ConsumerStatefulWidget {
  const NavigationBarAxisScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NavigationBarAxisScope> createState() =>
      _NavigationBarAxisScopeState();
}

class _NavigationBarAxisScopeState
    extends ConsumerState<NavigationBarAxisScope> {
  Axis? _lastResolvedAxis;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final axis = navigationTransitionAxis(
      context,
      useRail: context.appLayout.useRailNavigation,
    );
    if (axis == _lastResolvedAxis) return;
    _lastResolvedAxis = axis;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(navigationBarAxisProvider.notifier).setAxis(axis);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
