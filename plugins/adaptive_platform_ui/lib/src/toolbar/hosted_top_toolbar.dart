import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/ios26/ios26_native_toolbar.dart';
import 'duo_vertical_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// Height of the toolbar's content area, excluding the status bar.
const double kHostedToolbarHeight = 44.0;

/// What one page contributes to the top toolbar.
@immutable
class TopToolbarContent {
  const TopToolbarContent({
    this.title,
    this.titleOverlay,
    this.customLeading,
    this.impliesBack = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
    this.navigator,
  });

  /// No page owns the chrome, the page has no toolbar, or it draws a
  /// non-native bar of its own: nothing to show.
  ///
  /// With [titleOnly] the controls are left out, because the iPhone Duo
  /// vertical bar shows them instead.
  factory TopToolbarContent.of(ToolbarEntry? entry, {bool titleOnly = false}) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const TopToolbarContent();
    }
    return TopToolbarContent(
      title: appBar.title,
      titleOverlay: entry.titleOverlay,
      customLeading: titleOnly ? null : appBar.leading,
      impliesBack: !titleOnly && entry.impliesBackButton,
      actions: titleOnly
          ? const <AdaptiveAppBarAction>[]
          : appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
      navigator: entry.navigator,
    );
  }

  final String? title;

  /// A Flutter-drawn title (custom widget, or title with subtitle). The
  /// native title is left empty while one is shown.
  final Widget? titleOverlay;
  final Widget? customLeading;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;
  final NavigatorState? navigator;

  bool get isEmpty =>
      title == null &&
      titleOverlay == null &&
      customLeading == null &&
      !impliesBack &&
      actions.isEmpty;
}

/// The one top toolbar of the app. It stays where it is while pages come and
/// go underneath it; only its navigation item changes.
///
/// It works exactly like a system navigation bar: one native bar remains in
/// place for the whole app, and each page change replaces its item with
/// `setItems(animated: true)`. UIKit then plays the Liquid Glass button
/// insertion/removal animation itself, in step with the route transition.
/// Keeping a single bar also avoids creating a new glass bar view for every
/// pushed page.
class HostedTopToolbar extends StatelessWidget {
  const HostedTopToolbar({
    super.key,
    required this.blend,
    this.titleOnly = false,
  });

  final ToolbarBlend blend;

  /// True on iPhone Duo, where the controls live in the vertical bar.
  final bool titleOnly;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: blend, builder: _build);
  }

  Widget _build(BuildContext context, Widget? _) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = TopToolbarContent.of(upperEntry, titleOnly: titleOnly);
    final lower = TopToolbarContent.of(lowerEntry, titleOnly: titleOnly);
    final front = TopToolbarContent.of(blend.front, titleOnly: titleOnly);
    final showNativeBack =
        !titleOnly && front.impliesBack && front.customLeading == null;

    // The bar's backdrop belongs to the chrome, not to a page: it only fades
    // when the toolbar as a whole comes or goes. While a modal covers the
    // page it goes away entirely: a translucent white gradient above the
    // dialog barrier reads as a pale band along the top of the screen.
    final Animation<double> backdropOpacity = blend.ownerIsCovered
        ? kAlwaysDismissedAnimation
        : switch ((upper.isEmpty, lower.isEmpty)) {
            (false, false) => kAlwaysCompleteAnimation,
            (false, true) =>
              blend.isBlending && lowerEntry != null
                  ? blend.upperOpacity
                  : kAlwaysCompleteAnimation,
            (true, false) => blend.lowerOpacity,
            (true, true) => kAlwaysDismissedAnimation,
          };

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: titleOnly
            ? kDuoTitleBandHeight
            : kHostedToolbarHeight + topInset,
        child: IgnorePointer(
          ignoring: blend.ownerIsCovered,
          child: FadeTransition(
            opacity: blend.chromeOpacity,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                FadeTransition(
                  key: const ValueKey<String>('adaptive_toolbar_backdrop'),
                  opacity: backdropOpacity,
                  child: titleOnly
                      ? const DuoTitleBackdrop()
                      : const _Backdrop(),
                ),
                // One native bar stays alive for the whole app. Changing its
                // items lets UIKit animate the glass buttons themselves,
                // instead of fading a freshly created bar view.
                if (!front.isEmpty)
                  titleOnly
                      ? DuoToolbarTitle(
                          title: front.title,
                          titleWidget: front.titleOverlay,
                        )
                      : defaultTargetPlatform == TargetPlatform.iOS
                      ? IOS26NativeToolbar(
                          title: front.title,
                          titleWidget: front.titleOverlay,
                          leading: front.customLeading,
                          leadingText: showNativeBack ? '' : null,
                          onLeadingTap: showNativeBack
                              ? () => front.navigator?.maybePop()
                              : null,
                          actions: front.actions,
                          interactive: !blend.ownerIsCovered,
                          tintColor: front.tint,
                          showsGradient: false,
                          onActionTap: (index) {
                            if (index >= 0 && index < front.actions.length) {
                              front.actions[index].onPressed();
                            }
                          },
                        )
                      : _FallbackBar(content: front),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The soft gradient that keeps the bar readable over scrolling content.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final base = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            // Runs on below the bar for a smooth fade into the content.
            height:
                MediaQuery.viewPaddingOf(context).top +
                kHostedToolbarHeight +
                30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 0.7, 1.0],
                colors: [
                  base.withValues(alpha: 0.85),
                  base.withValues(alpha: 0.6),
                  base.withValues(alpha: 0.2),
                  base.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stand-in for the native bar where there is no UIKit (widget tests and
/// non-iOS previews).
class _FallbackBar extends StatelessWidget {
  const _FallbackBar({required this.content});

  final TopToolbarContent content;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kHostedToolbarHeight,
        child: Row(
          children: [
            if (content.customLeading != null)
              content.customLeading!
            else if (content.impliesBack)
              CupertinoButton(
                key: const ValueKey<String>('adaptive_toolbar_back_fallback'),
                padding: EdgeInsets.zero,
                onPressed: () => content.navigator?.maybePop(),
                child: const Icon(CupertinoIcons.back),
              ),
            Expanded(
              child: Center(
                child:
                    content.titleOverlay ??
                    (content.title != null ? Text(content.title!) : null),
              ),
            ),
            for (final action in content.actions)
              Builder(
                builder: (context) => CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      action.press(context, navigator: content.navigator),
                  child: action.icon != null
                      ? Icon(action.icon)
                      : Text(action.title ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
