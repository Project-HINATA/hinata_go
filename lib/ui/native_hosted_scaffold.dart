import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/app_update_provider.dart';
import '../providers/navigation_provider.dart';
import 'shell_state_sync.dart';

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
      _publishSelection();
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'selectTopLevel':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final index = arguments['index'] as int;
        if (index >= 0 && index < 3) {
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        }
      case 'nativeAction':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final actionStr = arguments['action'] as String?;
        if (actionStr != null) {
          ref.read(appActionNotifierProvider.notifier).execute(actionStr);
          final legacyAction = switch (actionStr) {
            'addFolder' => NativeShellAction.addFolder,
            'addCard' => NativeShellAction.addCard,
            _ => null,
          };
          if (legacyAction != null) {
            ref.read(nativeShellActionProvider.notifier).trigger(legacyAction);
          }
        }
    }
  }

  Future<void> _publishTabs(List<NavigationTab> tabs) =>
      _channel.invokeMethod('setTabs', {
        'tabs': tabs
            .map(
              (t) => {
                'index': t.index,
                'label': t.label,
                'symbol': t.iosSymbol,
                'hasBadge': t.hasBadge,
              },
            )
            .toList(),
      });

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

  Future<void> _publishSelection() => _channel.invokeMethod(
    'setSelectedIndex',
    {'index': widget.navigationShell.currentIndex},
  );

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
    _publishTabs(tabs);

    ref.listen(appUpdateProvider, (_, next) {
      _publishSettingsBadge(next.hasUpdate);
    });

    ref.listen<AppActionConfig?>(appActionNotifierProvider, (_, config) {
      _publishActionButton(config);
    });

    syncShellState(
      context,
      ref,
      widget.navigationShell.currentIndex,
      publishNative: true,
    );
    return Scaffold(body: widget.navigationShell);
  }
}
