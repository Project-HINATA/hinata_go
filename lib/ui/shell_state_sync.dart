import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../context_extensions.dart';
import '../providers/navigation_provider.dart';

const _channel = MethodChannel('dev.hinata.go/native_shell');

class NativeShellNavigatorObserver extends NavigatorObserver {
  void _publishCoverage() {
    _channel.invokeMethod('setScaffoldCovered', {
      'covered': navigator?.canPop() ?? false,
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _publishCoverage();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _publishCoverage();
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
      _channel.invokeMethod('setScaffoldCovered', {
        'covered': !isScaffoldVisible,
      });
    }
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.read(activeBranchProvider) != activeIndex) {
      ref.read(activeBranchProvider.notifier).setIndex(activeIndex);
    }
  });
}
