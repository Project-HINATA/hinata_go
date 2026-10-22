import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/adaptive_app_bar.dart';
import '../widgets/adaptive_app_bar_action.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';
import 'top_bar_accessory.dart';

/// The native bar mostly reacts to the first stretch of a scroll: its edge
/// effect, title and chip strip are settled well before this either way, so
/// larger offsets are not sent. Negative offsets (content pulled down past
/// the top) move the chip strip down with the large title. Beside a vertical
/// bar, where the bar follows the direction of every scroll, all of them are
/// sent.
const double _kMaxSentScrollOffset = 200;

/// How the native shell lays its chrome out right now, decided from the
/// system's traits: the pages lay themselves out for it.
@immutable
class NativeBarLayout {
  const NativeBarLayout({
    this.largeTitles = false,
    this.barHidden = false,
    this.verticalTabs = false,
    this.titleMargin,
  });

  factory NativeBarLayout.fromMap(Map<Object?, Object?> map) => NativeBarLayout(
    largeTitles: map['largeTitles'] == true,
    barHidden: map['barHidden'] == true,
    verticalTabs: map['verticalTabs'] == true,
    titleMargin: (map['titleMargin'] as num?)?.toDouble(),
  );

  /// Pages draw their large title and get the chip strip (the tab bar sits at
  /// the bottom of a compact-width window).
  final bool largeTitles;

  /// The shell hides the top bar (iPhone in landscape).
  final bool barHidden;

  /// The tabs run down a vertical bar (iPhone Duo).
  final bool verticalTabs;

  /// The leading margin of the bar's own title.
  final double? titleMargin;

  @override
  bool operator ==(Object other) =>
      other is NativeBarLayout &&
      other.largeTitles == largeTitles &&
      other.barHidden == barHidden &&
      other.verticalTabs == verticalTabs &&
      other.titleMargin == titleMargin;

  @override
  int get hashCode =>
      Object.hash(largeTitles, barHidden, verticalTabs, titleMargin);
}

/// Sends the page stack to the native top bar so a real UIKit
/// `UINavigationController` can push/pop its placeholder items.
///
/// The Flutter route stack stays authoritative. Only the bar item stack is
/// mirrored; page content and its transition remain Flutter's. Each page is
/// described as it is (its title, its wish for a large title, its chips);
/// the native shell decides how its layout shows it, and reports that layout
/// back in [layout].
class NativeTopBarBridge {
  NativeTopBarBridge({required this.blend}) {
    blend.onNativeTransition = _onTransition;
    blend.addListener(_onBlendChanged);
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const channelName = 'moe.neri.hinatago/native_top_bar';
  static const _channel = MethodChannel(channelName);

  final ToolbarBlend blend;
  final List<_NativePage> _pages = <_NativePage>[];
  int _nextToken = 0;
  bool _active = false;
  bool _covered = false;

  /// The native shell's layout, pushed whenever its traits change.
  ValueListenable<NativeBarLayout> get layout => _layout;
  final ValueNotifier<NativeBarLayout> _layout = ValueNotifier(
    const NativeBarLayout(),
  );

  /// The scroll offset of the page on top, which the native bar follows.
  ValueListenable<double>? _watchedScroll;

  /// Called from the host on every build. [active] is true wherever the
  /// native controller owns the top bar (every iOS 26+ window).
  void update({required bool active}) {
    if (active == _active) return;
    _active = active;
    if (active) {
      _reset(blend.owner);
      _sendCovered(blend.ownerIsCovered);
      // The shell pushes its layout as it changes; ask for the current one
      // too, in case it was pushed before this side listened.
      _channel
          .invokeMethod<Object?>('getLayout')
          .then((value) {
            if (value is Map) _layout.value = NativeBarLayout.fromMap(value);
          })
          .catchError((Object _) {});
    } else {
      _pages.clear();
      _watchScroll();
    }
  }

  void _onBlendChanged() {
    if (!_active) return;
    _sendCovered(blend.ownerIsCovered);
  }

  void _onTransition(NativeBarTransition transition) {
    if (!_active) return;
    switch (transition.kind) {
      case NativeBarTransitionKind.reset:
        _reset(transition.entry);
        break;
      case NativeBarTransitionKind.push:
        _push(transition.entry);
        break;
      case NativeBarTransitionKind.pop:
        _pop(transition.entry);
        break;
      case NativeBarTransitionKind.update:
        _update(transition.entry);
        break;
    }
  }

  _NativePage _page(ToolbarEntry? entry, int token) =>
      _NativePage.fromEntry(entry, token);

  void _reset(ToolbarEntry? entry) {
    final page = _page(entry, _nextToken++);
    _pages
      ..clear()
      ..add(page);
    _sendPage('reset', page);
  }

  void _push(ToolbarEntry? entry) {
    final page = _page(entry, _nextToken++);
    _pages.add(page);
    _sendPage('push', page);
  }

  void _update(ToolbarEntry? entry) {
    if (entry == null || _pages.isEmpty) return;
    final current = _pages.last;
    final next = _page(entry, current.token)..sentScroll = current.sentScroll;
    final item = _item(next);
    final signature = jsonEncode(item);
    next.signature = signature;
    _pages[_pages.length - 1] = next;
    // With the same signature the native bar keeps its items, but the page
    // may have rebuilt with fresh callbacks; native taps must reach those, not
    // the old ones.
    if (signature != current.signature) _send('update', {'item': item});
    _watchScroll();
  }

  /// Installs [page] in the native bar together with its scroll state, so a
  /// page that is already scrolled never shows its large-title look for a
  /// frame.
  void _sendPage(String method, _NativePage page) {
    final item = _item(page);
    page.signature = jsonEncode(item);
    final scroll = page.scrollState(_maxSentScrollOffset);
    page.sentScroll = scroll;
    _send(method, {'item': item, 'scroll': scroll.toMap()});
    _watchScroll();
  }

  void _pop(ToolbarEntry? uncovered) {
    if (_pages.length > 1) {
      _pages.removeLast();
      _send('pop', const <String, Object?>{});
      _watchScroll();
      return;
    }
    // A tab switch collapses the native stack to the page that was on top.
    // Popping it in Flutter uncovers another page, so replace that one.
    if (uncovered != null) _reset(uncovered);
  }

  Map<String, Object?> _item(_NativePage page) {
    final content = page.content;
    return <String, Object?>{
      'token': page.token,
      if (content.title != null) 'title': content.title!,
      'back': page.impliesBack,
      if (content.nativeLeading != null) 'leading': content.nativeLeading!.name,
      if (content.nativeLogo) 'logo': true,
      // The page draws a large title where the layout has them, and the bar
      // keeps its small title hidden until that has scrolled under it.
      if (page.largeTitle) ...{
        'largeTitle': true,
        'largeTitleHeight': kLargeTitleHeight,
        'largeTitleCollapseOffset': kLargeTitleCollapseOffset,
      },
      if (page.chips.isNotEmpty)
        'chips': [
          for (final chip in page.chips)
            {'title': chip.label, 'selected': chip.selected},
        ],
      if (page.actions.isNotEmpty)
        'actions': [for (final action in page.actions) action.toNativeMap()],
      if (content.tint != null) 'tint': content.tint!.toARGB32(),
    };
  }

  /// Follows the scroll offset of the page on top of the stack.
  void _watchScroll() {
    final next = _pages.isEmpty ? null : _pages.last.scrollOffset;
    if (!identical(next, _watchedScroll)) {
      _watchedScroll?.removeListener(_syncScroll);
      _watchedScroll = next;
      _watchedScroll?.addListener(_syncScroll);
    }
    _syncScroll();
  }

  /// Sends the top page's scroll state when it differs from what the native
  /// bar last received for that page.
  void _syncScroll() {
    if (!_active || _pages.isEmpty) return;
    final page = _pages.last;
    final scroll = page.scrollState(_maxSentScrollOffset);
    if (scroll == page.sentScroll) return;
    page.sentScroll = scroll;
    _send('scroll', {'token': page.token, ...scroll.toMap(), 'animated': true});
  }

  double get _maxSentScrollOffset =>
      _layout.value.verticalTabs ? double.infinity : _kMaxSentScrollOffset;

  void _sendCovered(bool covered) {
    if (_covered == covered) return;
    _covered = covered;
    _send('setCovered', {'covered': covered});
  }

  void _send(String method, Map<String, Object?> arguments) {
    _channel.invokeMethod<void>(method, arguments).catchError((Object _) {});
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) return null;
    if (call.method == 'layout') {
      _layout.value = NativeBarLayout.fromMap(arguments);
      return null;
    }
    final token = arguments['token'];
    _NativePage? page;
    for (final candidate in _pages) {
      if (candidate.token == token) {
        page = candidate;
        break;
      }
    }
    if (page == null) return null;

    switch (call.method) {
      case 'onBack':
        page.navigator?.maybePop();
        break;
      case 'onLeading':
        page.onNativeLeadingTap?.call();
        break;
      case 'onAction':
        final index = arguments['index'];
        if (index is int && index >= 0 && index < page.actions.length) {
          page.actions[index].onPressed();
        }
        break;
      case 'onMenu':
        final action = arguments['action'];
        final item = arguments['item'];
        if (action is int &&
            item is int &&
            action >= 0 &&
            action < page.actions.length) {
          page.actions[action].selectMenuItem(item);
        }
        break;
      case 'onChip':
      case 'onChipLongPress':
        final index = arguments['index'];
        if (index is int && index >= 0 && index < page.chips.length) {
          final chip = page.chips[index];
          if (call.method == 'onChip') {
            chip.onPressed();
          } else {
            chip.onLongPress?.call();
          }
        }
        break;
    }
    return null;
  }

  void dispose() {
    _layout.dispose();
    _watchedScroll?.removeListener(_syncScroll);
    blend.onNativeTransition = null;
    blend.removeListener(_onBlendChanged);
    _channel.setMethodCallHandler(null);
  }

  @visibleForTesting
  static MethodChannel get channel => _channel;
}

class _NativePage {
  _NativePage({
    required this.token,
    required this.entry,
    required this.content,
    required this.navigator,
    required this.impliesBack,
    required this.actions,
    required this.onNativeLeadingTap,
    required this.largeTitle,
    required this.chips,
    required this.scrollOffset,
  });

  factory _NativePage.fromEntry(ToolbarEntry? entry, int token) {
    final content = _BarContent.of(entry);
    final appBar = entry?.appBar;
    return _NativePage(
      token: token,
      entry: entry,
      content: content,
      navigator: entry?.navigator,
      impliesBack: entry?.impliesBackButton ?? false,
      actions: appBar?.actions ?? const <AdaptiveAppBarAction>[],
      onNativeLeadingTap: appBar?.onNativeLeadingTap,
      largeTitle:
          (appBar?.useNativeToolbar ?? false) &&
          (appBar?.largeTitle ?? false) &&
          content.title != null,
      chips: (appBar?.useNativeToolbar ?? false)
          ? appBar?.chips ?? const <AdaptiveToolbarChip>[]
          : const <AdaptiveToolbarChip>[],
      scrollOffset: entry?.scrollOffset,
    );
  }

  final int token;
  final ToolbarEntry? entry;
  final _BarContent content;
  final NavigatorState? navigator;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final VoidCallback? onNativeLeadingTap;

  /// Whether the page asks for a large title, which it draws where the
  /// native layout has large titles.
  final bool largeTitle;

  /// Shown by the native bar in a strip under itself, where the native layout
  /// has large titles.
  final List<AdaptiveToolbarChip> chips;
  final ValueListenable<double>? scrollOffset;
  String? signature;

  /// The scroll state the native bar last received for this page.
  _ScrollState? sentScroll;

  _ScrollState scrollState(double max) => _ScrollState(
    (scrollOffset?.value ?? 0).clamp(-_kMaxSentScrollOffset, max).toDouble(),
  );
}

/// How far a page's content is scrolled, as the native bar follows it: its
/// scroll-edge effect, the small title of a large-title page, the chips.
@immutable
class _ScrollState {
  const _ScrollState(this.offset);

  final double offset;

  Map<String, Object?> toMap() => <String, Object?>{'offset': offset};

  @override
  bool operator ==(Object other) =>
      other is _ScrollState && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

/// What a page puts in the native bar's title and leading slot; empty when
/// no page owns the bar or the page has no native toolbar.
@immutable
class _BarContent {
  const _BarContent({
    this.title,
    this.nativeLogo = false,
    this.nativeLeading,
    this.tint,
  });

  factory _BarContent.of(ToolbarEntry? entry) {
    final appBar = entry?.appBar;
    if (appBar == null || !appBar.useNativeToolbar) return const _BarContent();
    return _BarContent(
      title: appBar.title,
      nativeLogo: appBar.nativeLogo,
      nativeLeading: appBar.nativeLeading,
      tint: appBar.tintColor,
    );
  }

  final String? title;
  final bool nativeLogo;
  final NativeToolbarLeading? nativeLeading;
  final Color? tint;
}
