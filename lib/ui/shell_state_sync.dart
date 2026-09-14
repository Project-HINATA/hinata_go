import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../context_extensions.dart';
import '../providers/navigation_provider.dart';

const _channel = MethodChannel('dev.hinata.go/native_shell');

class NativeShellNavigatorObserver extends NavigatorObserver {
  void _publishCoverage([Route<dynamic>? topRoute]) {
    final covered = navigator?.canPop() ?? false;
    final hideNativeChrome =
        covered && topRoute is ModalRoute<dynamic> && topRoute.opaque;
    final isModalDimmed =
        covered && topRoute is ModalRoute<dynamic> && !topRoute.opaque;

    _channel.invokeMethod('setChromeVisibility', {
      'tabBarVisible': !hideNativeChrome,
      'dimmed': isModalDimmed,
    });
    _channel.invokeMethod('setScaffoldCovered', {
      'covered': covered,
      'hideNativeChrome': hideNativeChrome,
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _publishCoverage(newRoute);
  }
}

void syncShellState(
  BuildContext context,
  WidgetRef ref,
  int activeIndex, {
  bool publishNative = false,
}) {
  final isScaffoldVisible = context.modalRoute?.isCurrent ?? false;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.read(isScaffoldCoveredProvider) == isScaffoldVisible) {
      ref
          .read(isScaffoldCoveredProvider.notifier)
          .setCovered(!isScaffoldVisible);
    }
    if (publishNative) {
      _channel.invokeMethod('setChromeVisibility', {
        'tabBarVisible': isScaffoldVisible,
        'dimmed': false,
      });
      _channel.invokeMethod('setScaffoldCovered', {
        'covered': !isScaffoldVisible,
        'hideNativeChrome': false,
      });
    }
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.read(activeBranchProvider) != activeIndex) {
      ref.read(activeBranchProvider.notifier).setIndex(activeIndex);
    }
  });
}
