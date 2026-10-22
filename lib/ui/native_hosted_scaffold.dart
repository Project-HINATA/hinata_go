import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_update_provider.dart';
import '../providers/navigation_bar_provider.dart';
import '../providers/navigation_provider.dart';
import 'widgets/app_swipe_navigation.dart';

class NativeHostedScaffold extends ConsumerStatefulWidget {
  const NativeHostedScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<NativeHostedScaffold> createState() =>
      _NativeHostedScaffoldState();
}

class _NativeHostedScaffoldState extends ConsumerState<NativeHostedScaffold> {
  static const _channel = MethodChannel('dev.hinata.go/native_shell');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishTabs(ref.read(navigationTabsProvider));
      _publishSelection();
      _publishSettingsBadge(ref.read(appUpdateProvider).hasUpdate);
      _publishActionButton(ref.read(appActionNotifierProvider));
    });
  }

  @override
  void didUpdateWidget(covariant NativeHostedScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      // Finish Flutter's route frame before UIKit moves the shared view.
      // A switch UIKit started itself is already in place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishSelection();
      });
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'selectTopLevel':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final index = arguments['index'] as int;
        if (index >= 0 && index < 3) {
          final previousIndex = widget.navigationShell.currentIndex;
          debugPrint(
            '[NativeShell] Dart received selectTopLevel=$index '
            'current=$previousIndex',
          );
          // UIKit has already switched to the tab the user tapped.
          _nativeIndex = index;
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == previousIndex,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Brings UIKit back should the router have landed elsewhere.
            _publishSelection();
          });
          return {'accepted': true, 'index': index, 'previous': previousIndex};
        }
        return {'accepted': false, 'index': index};
      case 'nativeAction':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final actionStr = arguments['action'] as String?;
        if (actionStr != null) {
          ref.read(appActionNotifierProvider.notifier).execute(actionStr);
        }
        return null;
      default:
        return null;
    }
  }

  /// The last tab set sent to UIKit. Re-publishing the same titles, icons and
  /// badges on every Flutter rebuild churns the native tab bar's items, which
  /// can swallow taps, so an unchanged set is skipped.
  String? _lastTabsSignature;

  Future<void> _publishTabs(List<NavigationTab> tabs, {int? tint}) {
    final signature = [
      for (final t in tabs)
        '${t.index}|${t.label}|${t.iosSymbol}|${t.hasBadge}',
      'tint:$tint',
    ].join(';');
    if (signature == _lastTabsSignature) return Future<void>.value();
    _lastTabsSignature = signature;
    return _channel.invokeMethod('setTabs', {
      'tabs': tabs
          .map(
            (t) => {
              'index': t.index,
              'label': t.label,
              'symbol': t.iosSymbol,
              'hasBadge': t.hasBadge,
              'tint': ?tint,
            },
          )
          .toList(),
    });
  }

  Future<void> _publishActionButton(AppActionConfig? config) {
    if (config == null) {
      return _channel.invokeMethod('setActionButton', {'config': null});
    }

    final items = config.menuItems
        ?.map((item) => {'id': item.id, 'title': item.label})
        .toList();

    return _channel.invokeMethod('setActionButton', {
      'config': {
        'actionId': config.id,
        'label': config.tooltip,
        'symbol': config.nativeSymbol ?? 'plus',
        'items': items ?? [],
      },
    });
  }

  /// The tab UIKit has selected, as far as Dart knows.
  ///
  /// A tap switches UIKit first and reports it here. Sending the same index
  /// back is not only redundant: with two quick taps, the echo of the first
  /// would reach UIKit after the second and switch it back for a moment.
  int? _nativeIndex;

  Future<void> _publishSelection() {
    final index = widget.navigationShell.currentIndex;
    if (index == _nativeIndex) return Future<void>.value();
    _nativeIndex = index;
    debugPrint('[NativeShell] Flutter -> UIKit setSelectedIndex=$index');
    return _channel.invokeMethod('setSelectedIndex', {'index': index});
  }

  Future<void> _publishSettingsBadge(bool visible) =>
      _channel.invokeMethod('setSettingsBadge', {'visible': visible});

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(navigationTabsProvider);
    // Keep the system tab bar on the app's accent colour, including a
    // harmonised dynamic colour.
    _publishTabs(tabs, tint: Theme.of(context).colorScheme.primary.toARGB32());

    ref.listen(appUpdateProvider, (_, next) {
      _publishSettingsBadge(next.hasUpdate);
    });

    ref.listen<AppActionConfig?>(appActionNotifierProvider, (_, config) {
      _publishActionButton(config);
    });

    return Scaffold(
      body: AppSwipeNavigation(
        tabAxis: ref.watch(navigationBarAxisProvider),
        branchIndex: widget.navigationShell.currentIndex,
        onBranchSelected: (index) => widget.navigationShell.goBranch(index),
        child: widget.navigationShell,
      ),
    );
  }
}
