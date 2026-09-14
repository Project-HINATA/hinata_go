import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/navigation_provider.dart';

const _channel = MethodChannel('dev.hinata.go/native_shell');

/// Feeds the root navigator's route stack into [nativeShellCoverageProvider] and mirrors the result
/// onto the native chrome.
final nativeShellNavigatorObserverProvider =
    Provider<NativeShellNavigatorObserver>((ref) {
      var isAlive = true;
      ref.onDispose(() => isAlive = false);
      final coverage = ref.watch(nativeShellCoverageProvider.notifier);
      return NativeShellNavigatorObserver(
        onCoverageChanged: (next) {
          // The observer fires from inside the navigator's build phase, where providers must not be
          // modified, so the state is published once the frame is done.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isAlive) coverage.update(next);
          });
        },
      );
    });

/// Watches the root navigator and reports what the native shell should be showing.
///
/// It has to look at the whole route stack, not just the top route: a modal pushed on top of a
/// root-level page such as `/instances` must not bring the tab bar back, because the page below it
/// is still an opaque route that replaced the shell.
///
/// The shell's branches run their own navigators and forward their events here when
/// `notifyRootObserver` is left enabled, which would mix their routes into this stack. The router
/// therefore disables that forwarding.
class NativeShellNavigatorObserver extends NavigatorObserver {
  NativeShellNavigatorObserver({this.onCoverageChanged});

  final ValueChanged<NativeShellCoverage>? onCoverageChanged;

  /// The root navigator's routes, bottom first. The first entry is the shell that owns the tab bar.
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _publishCoverage();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _publishCoverage();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _publishCoverage();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) {
      if (newRoute != null) _routes.add(newRoute);
    } else if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
    _publishCoverage();
  }

  void _publishCoverage() {
    final topRoute = _routes.isEmpty ? null : _routes.last;
    final coverage = NativeShellCoverage(
      visibleRoute: _visibleRoute(),
      shellRoute: _routes.isEmpty ? null : _routes.first,
      modalOnTop: topRoute is ModalRoute<dynamic> && !topRoute.opaque,
    );

    onCoverageChanged?.call(coverage);

    _channel.invokeMethod('setChromeVisibility', {
      'tabBarVisible': !coverage.shellCovered,
      'dimmed': coverage.modalOnTop,
    });
  }

  /// The route the user is looking at: the top-most opaque route of the stack.
  Route<dynamic>? _visibleRoute() {
    for (var i = _routes.length - 1; i >= 0; i--) {
      final route = _routes[i];
      if (route is ModalRoute<dynamic> && route.opaque) return route;
    }
    return null;
  }
}

void syncShellState(BuildContext context, WidgetRef ref, int activeIndex) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.read(activeBranchProvider) != activeIndex) {
      ref.read(activeBranchProvider.notifier).setIndex(activeIndex);
    }
  });
}
