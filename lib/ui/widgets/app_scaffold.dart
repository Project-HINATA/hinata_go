import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import '../app_action_button.dart';

/// Whether the app draws iOS chrome (native toolbars and tab bar) instead of
/// Material app bars. Web renders exactly like Android.
bool get useCupertinoChrome => PlatformInfo.isIOS;

/// Whether the iOS chrome is the iPhone Duo vertical bar, where the top-level
/// tabs and the page controls run down the side of the screen. `null` before
/// the toolbar host has resolved the pose.
bool? isDuoVerticalBar(BuildContext context) {
  if (!useCupertinoChrome) return false;
  return ToolbarChromeScope.maybeOf(context)?.hostsDuoControls;
}

/// The axis a tab change slides along: sideways on a bottom tab bar, down the
/// screen when the tabs sit in the iPhone Duo vertical bar.
Axis navigationTransitionAxis(BuildContext context, {required bool useRail}) {
  if (isDuoVerticalBar(context) ?? false) return Axis.vertical;
  return useRail ? Axis.vertical : Axis.horizontal;
}

/// A page: a native Liquid Glass toolbar on iOS (laid out in the vertical bar on
/// iPhone Duo), a Material app bar with a floating action button elsewhere.
///
/// The page describes its title and actions once; [primaryAction] becomes the
/// floating action button on Material and the trailing toolbar item on iOS.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.primaryAction,
    this.leading,
    this.materialAppBar,
    this.showMaterialAppBar = true,
    this.materialFloatingActionButton,
    this.backgroundColor,
  });

  final Widget body;
  final String? title;

  /// Replaces [title] in the iOS toolbar.
  final Widget? titleWidget;
  final List<AdaptiveAppBarAction> actions;
  final AppActionConfig? primaryAction;
  final Widget? leading;

  /// Replaces the app bar built from [title] and [actions] on Material.
  final PreferredSizeWidget? materialAppBar;

  /// Material pages drop their app bar where the navigation rail takes over.
  final bool showMaterialAppBar;

  /// Replaces the button built from [primaryAction] on Material.
  final Widget? materialFloatingActionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (useCupertinoChrome) {
      final toolbarAction = primaryAction == null
          ? null
          : buildToolbarAction(primaryAction!);
      final toolbarActions = [...actions, ?toolbarAction];

      return AdaptiveScaffold(
        backgroundColor: backgroundColor,
        appBar: title == null && titleWidget == null && toolbarActions.isEmpty
            ? null
            : AdaptiveAppBar(
                title: title,
                titleWidget: titleWidget,
                actions: toolbarActions,
                leading: leading,
              ),
        // Pages are built from Material widgets, which need a Material ancestor
        // that the Cupertino page scaffold does not provide.
        body: Material(type: MaterialType.transparency, child: body),
      );
    }

    return AdaptiveScaffold(
      backgroundColor: backgroundColor,
      appBar: showMaterialAppBar
          ? AdaptiveAppBar(
              title: title,
              actions: actions,
              leading: leading,
              appBar: materialAppBar,
            )
          : null,
      floatingActionButton:
          materialFloatingActionButton ??
          (primaryAction == null
              ? null
              : buildAppActionButton(context, config: primaryAction!)),
      body: body,
    );
  }
}
