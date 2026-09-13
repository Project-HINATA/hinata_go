import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../l10n/l10n.dart';
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
      _publishSelection();
      _publishSettingsBadge(ref.read(appUpdateProvider).hasUpdate);
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
        final action = switch (arguments['action']) {
          'addFolder' => NativeShellAction.addFolder,
          'addCard' => NativeShellAction.addCard,
          _ => null,
        };
        if (action != null) {
          ref.read(nativeShellActionProvider.notifier).trigger(action);
        }
    }
  }

  Future<void> _publishSelection() => _channel.invokeMethod(
    'setSelectedIndex',
    {'index': widget.navigationShell.currentIndex},
  );

  Future<void> _publishSettingsBadge(bool visible) =>
      _channel.invokeMethod('setSettingsBadge', {'visible': visible});

  Future<void> _publishLocalizedStrings(AppLocalizations localizations) =>
      _channel.invokeMethod('setLocalizedStrings', {
        'scan': localizations.scan,
        'cards': localizations.cards,
        'settings': localizations.settings,
        'addCard': localizations.addCard,
        'newFolder': localizations.newFolder,
      });

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _publishLocalizedStrings(AppLocalizations.of(context));
    ref.listen(appUpdateProvider, (_, next) {
      _publishSettingsBadge(next.hasUpdate);
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
