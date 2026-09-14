import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/app_host_mode.dart';
import '../providers/navigation_provider.dart';

export '../providers/navigation_provider.dart'
    show AppActionConfig, AppActionItem;

/// Unified action button builder across platforms.
///
/// - On [AppHostMode.nativeIOS]: registers the action configuration with
///   the native shell, which renders a native Liquid Glass (`.glass()`) button
///   and handles taps/menus via platform channel.
/// - On [AppHostMode.flutterShell]: renders a Material 3 FloatingActionButton
///   (or menu of FABs if [AppActionConfig.menuItems] is provided).
Widget? buildAppActionButton(
  BuildContext context,
  WidgetRef ref, {
  required AppActionConfig config,
}) {
  final hostMode = ref.watch(appHostModeProvider);

  if (!config.visible) {
    if (hostMode == AppHostMode.nativeIOS) {
      return const _AppActionRegistrar(config: null);
    }
    return null;
  }

  if (hostMode == AppHostMode.nativeIOS) {
    return _AppActionRegistrar(config: config);
  }

  if (config.menuItems != null && config.menuItems!.isNotEmpty) {
    return _FlutterMenuAction(config: config);
  }

  if (config.label != null) {
    return FloatingActionButton.extended(
      onPressed: config.onPressed,
      icon: Icon(config.icon),
      label: Text(config.label!),
      tooltip: config.tooltip,
    );
  }

  return FloatingActionButton(
    onPressed: config.onPressed,
    tooltip: config.tooltip,
    child: Icon(config.icon),
  );
}

class _FlutterMenuAction extends StatelessWidget {
  final AppActionConfig config;

  const _FlutterMenuAction({required this.config});

  @override
  Widget build(BuildContext context) {
    final items = config.menuItems!;
    if (items.length == 1) {
      final item = items.first;
      return FloatingActionButton(
        heroTag: item.id,
        onPressed: item.onPressed,
        tooltip: item.label,
        child: Icon(item.icon ?? config.icon),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 1; i < items.length; i++) ...[
          FloatingActionButton.small(
            heroTag: items[i].id,
            onPressed: items[i].onPressed,
            tooltip: items[i].label,
            child: Icon(items[i].icon ?? Icons.add),
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          heroTag: items.first.id,
          onPressed: items.first.onPressed,
          tooltip: items.first.label,
          child: Icon(items.first.icon ?? config.icon),
        ),
      ],
    );
  }
}

class _AppActionRegistrar extends ConsumerStatefulWidget {
  final AppActionConfig? config;

  const _AppActionRegistrar({required this.config});

  @override
  ConsumerState<_AppActionRegistrar> createState() =>
      _AppActionRegistrarState();
}

class _AppActionRegistrarState extends ConsumerState<_AppActionRegistrar> {
  late final AppActionNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(appActionNotifierProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _AppActionRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _notifier.clear();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final isCovered = ref.read(isScaffoldCoveredProvider);
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;

    if (!isCurrent || isCovered || widget.config == null) {
      _notifier.clear();
    } else {
      _notifier.setConfig(widget.config!);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isScaffoldCoveredProvider, (previous, next) => _sync());
    ref.listen(activeBranchProvider, (previous, next) => _sync());
    return const SizedBox.shrink();
  }
}
