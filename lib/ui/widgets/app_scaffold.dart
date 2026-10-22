import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/navigation_provider.dart';
import '../app_action_button.dart';
import '../app_layout.dart';

/// Whether the app draws iOS chrome (native toolbars and tab bar) instead of
/// Material app bars. Web renders exactly like Android.
bool get useCupertinoChrome => PlatformInfo.isIOS;

/// The axis a tab change slides along, following where the tabs are.
///
/// * The native shell reports when its tabs run down a vertical bar (iPhone
///   Duo): tabs move vertically. Elsewhere the native tab bar is horizontal.
/// * Android and web switch to a side rail in landscape: vertically.
Axis navigationTransitionAxis(BuildContext context, {required bool useRail}) =>
    tabTransitionAxis(
      usesNativeBar: useCupertinoChrome,
      verticalTabs: ToolbarChromeScope.maybeOf(context)?.verticalTabs ?? false,
      useRail: useRail,
    );

/// The rule behind [navigationTransitionAxis], without a [BuildContext].
@visibleForTesting
Axis tabTransitionAxis({
  required bool usesNativeBar,
  required bool verticalTabs,
  required bool useRail,
}) {
  if (usesNativeBar) return verticalTabs ? Axis.vertical : Axis.horizontal;
  return useRail ? Axis.vertical : Axis.horizontal;
}

/// Whether the page should draw a top bar on iOS.
///
/// The native shell hides its bar where height is compact (an iPhone in
/// landscape) and says so; the page then floats its controls instead. Without
/// the native bar (before iOS 26) the same rule is applied to the page's own
/// bar.
bool showsIOSTopBar(BuildContext context) {
  final chrome = ToolbarChromeScope.maybeOf(context);
  return shouldShowIOSTopBar(
    usesNativeBar: useCupertinoChrome,
    topBarHidden: chrome?.nativeTopBarOwned ?? false
        ? chrome!.topBarHidden
        : context.appLayout.isCompactLandscapePhone,
  );
}

/// The rule behind [showsIOSTopBar], without a [BuildContext].
@visibleForTesting
bool shouldShowIOSTopBar({
  required bool usesNativeBar,
  required bool topBarHidden,
}) {
  return usesNativeBar && !topBarHidden;
}

/// Whether a Material page draws its own top app bar.
///
/// The rail already provides navigation for the pages beside it in landscape,
/// so their bar would only repeat that and take a strip off an already short
/// screen. Everywhere else — portrait, pushed routes, standalone pages — the
/// page keeps its bar.
@visibleForTesting
bool shouldShowMaterialTopBar({
  required bool landscape,
  required bool railHosted,
}) {
  return !(landscape && railHosted);
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
class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.primaryAction,
    this.leading,
    this.nativeLogo = false,
    this.largeTitle = false,
    this.chips,
    this.nativeLeading,
    this.onNativeLeadingTap,
    this.materialAppBar,
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

  /// Show the HINATA logo next to [title] in the native iPhone top bar.
  final bool nativeLogo;

  /// Show the title large above the content on iPhone, collapsing into the
  /// native top bar once the content scrolls under it, like the top-level
  /// pages of system apps. The page's main scroll view must let its content
  /// run under the top bar (no top [SafeArea] around it) for the title to
  /// scroll away with it.
  final bool largeTitle;

  /// Shown by the native iPhone top bar as Liquid Glass chips under itself.
  /// The page still draws its own selector wherever
  /// [TopBarAccessoryScope.isNative] is false.
  final List<AdaptiveToolbarChip>? chips;

  /// A leading control the native iPhone top bar can build, for pages whose
  /// Flutter leading widget cannot be represented by UIKit.
  final NativeToolbarLeading? nativeLeading;
  final VoidCallback? onNativeLeadingTap;

  /// Replaces the app bar built from [title] and [actions] on Material.
  final PreferredSizeWidget? materialAppBar;

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
  Widget build(BuildContext context, WidgetRef ref) {
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
                nativeLogo: nativeLogo,
                largeTitle: largeTitle,
                chips: chips,
                nativeLeading: nativeLeading,
                onNativeLeadingTap: onNativeLeadingTap,
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

    final layout = context.appLayout;
    final showTopBar = shouldShowMaterialTopBar(
      landscape: layout.isLandscape,
      railHosted: RailHostScope.isHosted(context),
    );

    return AdaptiveScaffold(
      backgroundColor: backgroundColor,
      appBar: showTopBar
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
