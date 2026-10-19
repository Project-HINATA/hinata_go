import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/ios26/ios26_glass_capsule.dart';
import 'duo_vertical_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// The one vertical bar of the app. It never moves; only its controls follow
/// the page that owns the chrome. A single action bar stays alive for the
/// whole app, so pushing a page updates its native glass capsule in place
/// instead of creating a new one and fading it in. The tab bar and the shared
/// back button remain in their own stable layers.
class HostedDuoBar extends StatelessWidget {
  const HostedDuoBar({super.key, required this.blend, required this.regions});

  final ToolbarBlend blend;
  final List<ReservedRegion> regions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: blend, builder: _build);
  }

  Widget _build(BuildContext context, Widget? _) {
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = _BarContent.of(upperEntry);
    final lower = _BarContent.of(lowerEntry);
    final front = _BarContent.of(blend.front);
    final frontTabs = blend.registry.tabBarOwnerFor(blend.front);
    final upperOwns = blend.upperOwns;
    final upperOpacity = blend.upperOpacity;
    final lowerOpacity = blend.lowerOpacity;

    // The tab bar belongs to the tab layout, not to a page: it stays still
    // while pages inside the tabs change, and fades with the page when the
    // navigation leaves or enters the tabs.
    final upperTabs = blend.registry.tabBarOwnerFor(upperEntry);
    final lowerTabs = blend.registry.tabBarOwnerFor(lowerEntry);
    final tabLayers = <(ToolbarEntry, Animation<double>)>[
      if (lowerTabs != null && lowerTabs.id != upperTabs?.id)
        (lowerTabs, lowerOpacity),
      if (upperTabs != null)
        (
          upperTabs,
          lowerTabs?.id == upperTabs.id
              ? kAlwaysCompleteAnimation
              : upperOpacity,
        ),
    ];

    // The back button is one control shared by every page, drawn in a layer
    // of its own: it stays still when both pages have it, and fades with the
    // only page that has it otherwise. Page layers just keep its slot free.
    final Animation<double>? backOpacity = switch ((
      upper.impliesBack,
      lower.impliesBack,
    )) {
      (true, true) => kAlwaysCompleteAnimation,
      (true, false) => upperOpacity,
      (false, true) => lowerOpacity,
      (false, false) => null,
    };

    // Dimmed and inert while a dialog or sheet covers the owner. Every layer
    // is keyed, so a page's native buttons survive the start and the end of a
    // blend instead of being torn down and rebuilt.
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        opacity: blend.chromeOpacity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // One action capsule stays alive for the whole app; updating its
            // items keeps the native glass views instead of rebuilding them
            // for every pushed page. The wrapper keeps the last controls for
            // one short fade when the incoming page has none, so the capsule
            // does not simply vanish.
            _DuoActionsLayer(
              content: front,
              reservedTabs: frontTabs?.tabBar?.items?.length ?? 0,
              regions: regions,
              interactive: !blend.ownerIsCovered,
            ),
            if (backOpacity != null)
              FadeTransition(
                key: const ValueKey<String>('adaptive_toolbar_back'),
                opacity: backOpacity,
                alwaysIncludeSemantics: true,
                child: ExcludeSemantics(
                  // Fading out with the page that is leaving.
                  excluding: !(upperOwns ? upper : lower).impliesBack,
                  child: DuoVerticalBar(
                    leading: DuoBarBackButton(
                      onPressed: () =>
                          (upperOwns ? upper : lower).navigator?.maybePop(),
                    ),
                    regions: regions,
                  ),
                ),
              ),
            for (final (tabs, opacity) in tabLayers)
              FadeTransition(
                key: ValueKey<(String, Object)>(('adaptive_tabs', tabs.id)),
                opacity: opacity,
                alwaysIncludeSemantics: true,
                child: ExcludeSemantics(
                  excluding: tabs.id != upperTabs?.id,
                  child: DuoVerticalBar(
                    tabBar: tabs.tabBar,
                    // Tabs stay tappable in this layer: it is drawn only for
                    // the page that owns the chrome and is blended away when
                    // a modal covers it.
                    interactive: !blend.ownerIsCovered,
                    regions: regions,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the page controls in the vertical bar while a page with controls
/// leaves, so the action capsule fades instead of disappearing outright.
class _DuoActionsLayer extends StatefulWidget {
  const _DuoActionsLayer({
    required this.content,
    required this.reservedTabs,
    required this.regions,
    required this.interactive,
  });

  final _BarContent content;
  final int reservedTabs;
  final List<ReservedRegion> regions;
  final bool interactive;

  @override
  State<_DuoActionsLayer> createState() => _DuoActionsLayerState();
}

class _DuoActionsLayerState extends State<_DuoActionsLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  _BarContent? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.content.isEmpty ? null : widget.content;
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _shown == null ? 0 : 1,
    );
  }

  @override
  void didUpdateWidget(covariant _DuoActionsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.content;
    if (!incoming.isEmpty) {
      final wasEmpty = _shown == null;
      _shown = incoming;
      if (wasEmpty) _fade.value = 0;
      _fade.forward();
    } else if (_shown != null) {
      _fade.reverse().whenComplete(() {
        if (!mounted || !widget.content.isEmpty) return;
        setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _fade,
      child: DuoVerticalBar(
        key: const ValueKey<String>('adaptive_duo_page_controls'),
        leading:
            shown.customLeading ??
            (shown.impliesBack
                ? const SizedBox.square(dimension: IOS26GlassCapsule.width)
                : null),
        interactive: widget.interactive && !widget.content.isEmpty,
        actions: shown.actions,
        reservedTabs: widget.reservedTabs,
        tint: shown.tint,
        regions: widget.regions,
        navigator: shown.navigator,
      ),
    );
  }
}

/// What one page contributes to the bar.
class _BarContent {
  const _BarContent({
    this.customLeading,
    this.impliesBack = false,
    this.navigator,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
  });

  /// No page owns the chrome (a page without an [AdaptiveScaffold] is in
  /// front), the page has no toolbar, or it draws a non-native bar of its
  /// own: the bar stays in place, empty, instead of showing another page's
  /// controls.
  factory _BarContent.of(ToolbarEntry? entry) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const _BarContent();
    }
    return _BarContent(
      customLeading: appBar.leading,
      impliesBack: entry.impliesBackButton,
      navigator: entry.navigator,
      actions: appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
    );
  }

  final Widget? customLeading;
  final bool impliesBack;
  final NavigatorState? navigator;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;

  bool get isEmpty => customLeading == null && !impliesBack && actions.isEmpty;
}
