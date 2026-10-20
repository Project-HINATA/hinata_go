import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/adaptive_app_bar_action.dart';
import 'hosted_top_toolbar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// Sends the page stack to the native top bar so a real UIKit
/// `UINavigationController` can push/pop its placeholder items.
///
/// The Flutter route stack stays authoritative. Only the bar item stack is
/// mirrored; page content and its transition remain Flutter's.
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
  bool _visible = false;
  bool _covered = false;

  /// Called from the host on every build. [active] is true wherever the
  /// native controller owns the top bar (every iOS 26+ window); [visible] is
  /// false in landscape where the app intentionally has no top bar.
  void update({required bool active, required bool visible}) {
    if (active != _active) {
      _active = active;
      if (active) {
        _reset(blend.owner);
        _sendVisible(visible);
        _sendCovered(blend.ownerIsCovered);
      } else {
        _sendVisible(false);
        _pages.clear();
      }
      return;
    }
    if (!active) return;
    _sendVisible(visible);
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

  void _reset(ToolbarEntry? entry) {
    final page = _NativePage.fromEntry(entry, _nextToken++);
    _pages
      ..clear()
      ..add(page);
    _sendPage('reset', page);
  }

  void _push(ToolbarEntry? entry) {
    final page = _NativePage.fromEntry(entry, _nextToken++);
    _pages.add(page);
    _sendPage('push', page);
  }

  void _update(ToolbarEntry? entry) {
    if (entry == null || _pages.isEmpty) return;
    final current = _pages.last;
    final next = _NativePage.fromEntry(entry, current.token);
    final item = _item(next);
    final signature = jsonEncode(item);
    next.signature = signature;
    if (signature == current.signature) {
      // The native bar keeps the same items, but the page may have rebuilt
      // with fresh callbacks; native taps must reach those, not the old ones.
      _pages[_pages.length - 1] = next;
      return;
    }
    _pages[_pages.length - 1] = next;
    _send('update', {'item': item});
  }

  void _sendPage(String method, _NativePage page) {
    final item = _item(page);
    page.signature = jsonEncode(item);
    _send(method, {'item': item});
  }

  void _pop(ToolbarEntry? uncovered) {
    if (_pages.length > 1) {
      _pages.removeLast();
      _send('pop', const <String, Object?>{});
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
      if (page.actions.isNotEmpty)
        'actions': [for (final action in page.actions) action.toNativeMap()],
      if (content.tint != null) 'tint': content.tint!.toARGB32(),
    };
  }

  void _sendVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _send('setVisible', {'visible': visible});
  }

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
    }
    return null;
  }

  void dispose() {
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
    required this.content,
    required this.navigator,
    required this.impliesBack,
    required this.actions,
    required this.onNativeLeadingTap,
  });

  factory _NativePage.fromEntry(ToolbarEntry? entry, int token) {
    return _NativePage(
      token: token,
      content: TopToolbarContent.of(entry),
      navigator: entry?.navigator,
      impliesBack: entry?.impliesBackButton ?? false,
      actions: entry?.appBar?.actions ?? const <AdaptiveAppBarAction>[],
      onNativeLeadingTap: entry?.appBar?.onNativeLeadingTap,
    );
  }

  final int token;
  final TopToolbarContent content;
  final NavigatorState? navigator;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final VoidCallback? onNativeLeadingTap;
  String? signature;
}
