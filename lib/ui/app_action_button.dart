import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import '../providers/navigation_provider.dart';

export '../providers/navigation_provider.dart'
    show AppActionConfig, AppActionItem;

/// The page's primary action as a Material 3 FloatingActionButton, or a column
/// of extended FABs when [AppActionConfig.menuItems] is provided.
Widget? buildAppActionButton(
  BuildContext context, {
  required AppActionConfig config,
}) {
  if (!config.visible) return null;

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

/// The page's primary action as a native toolbar item. A config with menu items
/// opens a native menu from the toolbar, like the "+" of a system app.
AdaptiveAppBarAction? buildToolbarAction(AppActionConfig config) {
  if (!config.visible) return null;

  final items = config.menuItems;
  if (items != null && items.isNotEmpty) {
    return AdaptiveAppBarAction(
      iosSymbol: config.nativeSymbol ?? 'plus',
      icon: config.icon,
      label: config.tooltip,
      menuItems: [
        for (final item in items)
          AdaptivePopupMenuItem<String>(
            label: item.label,
            icon: item.nativeSymbol,
            value: item.id,
          ),
      ],
      onMenuItemSelected: (index, _) => items[index].onPressed(),
    );
  }

  final onPressed = config.onPressed;
  if (onPressed == null) return null;

  return AdaptiveAppBarAction(
    iosSymbol: config.nativeSymbol ?? 'plus',
    icon: config.icon,
    label: config.tooltip,
    onPressed: onPressed,
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
      return _LongPressable(
        item: item,
        child: FloatingActionButton(
          heroTag: item.id,
          onPressed: item.onPressed,
          tooltip: item.label,
          child: Icon(item.icon ?? config.icon),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final item in items.reversed) ...[
          if (item != items.last) const SizedBox(height: 12),
          _LongPressable(
            item: item,
            child: FloatingActionButton.extended(
              heroTag: item.id,
              onPressed: item.onPressed,
              tooltip: item.label,
              icon: Icon(item.icon ?? config.icon),
              extendedTextStyle: Theme.of(context).textTheme.labelLarge,
              label: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 112,
                ),
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LongPressable extends StatelessWidget {
  final AppActionItem item;
  final Widget child;

  const _LongPressable({required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    final onLongPress = item.onLongPress;
    if (onLongPress == null) return child;
    return GestureDetector(
      onLongPress: onLongPress,
      // The button's tooltip would otherwise take the long press for itself.
      child: TooltipTheme(
        data: TooltipTheme.of(
          context,
        ).copyWith(triggerMode: TooltipTriggerMode.manual),
        child: child,
      ),
    );
  }
}
