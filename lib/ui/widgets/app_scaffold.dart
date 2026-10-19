import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/navigation_provider.dart';
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

/// The axis a tab change slides along, decided from the platform rules for
/// where the bar sits, not from measuring the bar.
///
/// * iPhone Duo's vertical bar runs down the screen: tabs move vertically.
/// * iPhone keeps its bar at the bottom in both orientations: sideways.
/// * Android and web switch to a side rail in landscape: vertically.
Axis navigationTransitionAxis(BuildContext context, {required bool useRail}) =>
    tabTransitionAxis(
      usesNativeBar: useCupertinoChrome,
      duoVerticalBar: isDuoVerticalBar(context) ?? false,
      useRail: useRail,
    );

/// The rule behind [navigationTransitionAxis], without a [BuildContext].
@visibleForTesting
Axis tabTransitionAxis({
  required bool usesNativeBar,
  required bool duoVerticalBar,
  required bool useRail,
}) {
  if (usesNativeBar) return duoVerticalBar ? Axis.vertical : Axis.horizontal;
  return useRail ? Axis.vertical : Axis.horizontal;
}

/// Whether the page should draw a top bar on iOS.
///
/// Portrait keeps the bar. In landscape it would cost a strip of an already
/// short screen, so it is dropped — except on the iPhone Duo, whose vertical
/// tab bar shows icons only and leaves the page title with nowhere else to go.
bool showsIOSTopBar(BuildContext context) => shouldShowIOSTopBar(
  usesNativeBar: useCupertinoChrome,
  landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
  duoVerticalBar: isDuoVerticalBar(context) ?? false,
);

/// The rule behind [showsIOSTopBar], without a [BuildContext].
@visibleForTesting
bool shouldShowIOSTopBar({
  required bool usesNativeBar,
  required bool landscape,
  required bool duoVerticalBar,
}) {
  if (!usesNativeBar) return false;
  if (!landscape) return true;
  return duoVerticalBar;
}

/// Hides a page's floating controls while a modal covers the page.
///
/// They are platform views, so a Flutter barrier paints underneath them and
/// cannot make them inert; taking them out of the tree is the reliable way to
/// keep them from being tapped behind a dialog.
class _HideWhenCovered extends ConsumerWidget {
  const _HideWhenCovered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covered = ref.watch(nativeShellCoverageProvider).modalOnTop;
    return covered ? const SizedBox.shrink() : child;
  }
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

  /// The floating leading control where the top bar is dropped: the page's
  /// own leading, or the back button the toolbar would have implied.
  Widget? _floatingLeading(BuildContext context) {
    if (leading != null) return _floatingColumn([leading!]);
    final route = ModalRoute.of(context);
    if (route == null || !route.canPop) return null;
    return _floatingColumn([
      _floatingToolbarButton(
        symbol: 'chevron.left',
        label: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ]);
  }

  /// The floating corner controls used where the top bar is dropped: round
  /// glass buttons with the same actions a toolbar would carry.
  Widget? _floatingActions(BuildContext context) {
    final buttons = <Widget>[
      for (final action in actions) _floatingAction(action),
      if (primaryAction != null)
        _floatingToolbarButton(
          symbol: primaryAction!.nativeSymbol ?? 'plus',
          label: primaryAction!.tooltip,
          onPressed: primaryAction!.onPressed,
          menuItems: primaryAction!.menuItems,
        ),
    ];
    return _floatingColumn(buttons);
  }

  Widget _floatingAction(AdaptiveAppBarAction action) {
    return _floatingToolbarButton(
      symbol: action.iosSymbol ?? 'ellipsis',
      label: action.effectiveLabel ?? '',
      onPressed: action.hasMenu ? null : action.onPressed,
      menuItems: action.menuItems
          ?.whereType<AdaptivePopupMenuItem<dynamic>>()
          .map(
            (entry) => AppActionItem(
              id: entry.label,
              label: entry.label,
              icon: entry.icon is IconData ? entry.icon as IconData : null,
              nativeSymbol: entry.icon is String ? entry.icon as String : null,
              onPressed: () =>
                  action.selectMenuItem(action.menuItems!.indexOf(entry)),
            ),
          )
          .toList(),
    );
  }

  Widget _floatingToolbarButton({
    required String symbol,
    required String label,
    required VoidCallback? onPressed,
    List<AppActionItem>? menuItems,
  }) {
    if (menuItems != null && menuItems.isNotEmpty) {
      return AdaptivePopupMenuButton.icon<String>(
        icon: symbol,
        iconSize: 20,
        size: 48,
        buttonStyle: PopupButtonStyle.glass,
        items: [
          for (final item in menuItems)
            AdaptivePopupMenuItem<String>(
              label: item.label,
              icon: item.nativeSymbol ?? item.icon,
              value: item.id,
            ),
        ],
        onSelected: (index, item) => menuItems[index].onPressed(),
      );
    }
    return AdaptiveButton.sfSymbol(
      onPressed: onPressed ?? () {},
      sfSymbol: SFSymbol(symbol, size: 20),
      size: AdaptiveButtonSize.large,
      useSmoothRectangleBorder: false,
      enabled: onPressed != null,
    );
  }

  Widget? _floatingColumn(List<Widget> buttons) {
    if (buttons.isEmpty) return null;
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final button in buttons) ...[
            SizedBox.square(dimension: 48, child: button),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (useCupertinoChrome) {
      final toolbarAction = primaryAction == null
          ? null
          : buildToolbarAction(primaryAction!);
      final toolbarActions = [...actions, ?toolbarAction];
      final showTopBar = showsIOSTopBar(context);

      return AdaptiveScaffold(
        backgroundColor: backgroundColor,
        appBar:
            !showTopBar ||
                (title == null && titleWidget == null && toolbarActions.isEmpty)
            ? null
            : AdaptiveAppBar(
                title: title,
                titleWidget: titleWidget,
                actions: toolbarActions,
                leading: leading,
              ),
        // Pages are built from Material widgets, which need a Material ancestor
        // that the Cupertino page scaffold does not provide.
        body: Material(
          type: MaterialType.transparency,
          child: showTopBar
              ? body
              : Stack(
                  children: [
                    Positioned.fill(child: body),
                    // Without a top bar the same controls float in the
                    // corners: navigation leading, page actions trailing.
                    if (_floatingLeading(context) case final control?)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: _HideWhenCovered(child: control),
                      ),
                    if (_floatingActions(context) case final controls?)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _HideWhenCovered(child: controls),
                      ),
                  ],
                ),
        ),
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
