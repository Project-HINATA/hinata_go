import 'package:flutter/widgets.dart';

import '../platform/platform_info.dart';
import 'native_top_bar_bridge.dart';
import 'toolbar_blend.dart';
import 'toolbar_chrome_scope.dart';
import 'toolbar_registry.dart';

/// Connects the pages to a native UIKit top bar that lives above the
/// navigator.
///
/// Install it once around the navigator (an app `builder` is the right
/// place). It owns a [ToolbarRegistry] that every [AdaptiveScaffold] below
/// publishes its app bar to, and mirrors the page stack into the native shell's
/// `UINavigationController`s, which draw the bar: UIKit then places the bar,
/// its items and the tabs for whatever device and window it runs in.
///
/// The native shell also reports how it laid its chrome out, from the system's
/// traits, and the host passes that to the pages in a [ToolbarChromeScope].
/// Without the native shell ([nativeTopBar] false, or before iOS 26) the host
/// does nothing and pages draw their own toolbars.
///
/// Works with any router: it depends on nothing but the widget tree.
class AdaptiveToolbarHost extends StatefulWidget {
  const AdaptiveToolbarHost({
    super.key,
    required this.child,
    this.nativeTopBar = false,
    @visibleForTesting this.debugIOS26,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// Whether a native UIKit `UINavigationController` above the Flutter view
  /// owns the top bar.
  final bool nativeTopBar;

  /// Replaces the iOS 26 check, so the host can be exercised in widget tests.
  @visibleForTesting
  final bool? debugIOS26;

  @override
  State<AdaptiveToolbarHost> createState() => _AdaptiveToolbarHostState();
}

class _AdaptiveToolbarHostState extends State<AdaptiveToolbarHost>
    with TickerProviderStateMixin {
  final ToolbarRegistry _registry = ToolbarRegistry();
  late final ToolbarBlend _blend;
  late final NativeTopBarBridge _nativeBar;

  @override
  void initState() {
    super.initState();
    _blend = ToolbarBlend(registry: _registry, vsync: this);
    _nativeBar = NativeTopBarBridge(blend: _blend);
    _nativeBar.layout.addListener(_onLayoutChanged);
  }

  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nativeBar.layout.removeListener(_onLayoutChanged);
    _nativeBar.dispose();
    _blend.dispose();
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.nativeTopBar &&
        (widget.debugIOS26 ?? PlatformInfo.isIOS26OrHigher());
    _nativeBar.update(active: active);
    final layout = _nativeBar.layout.value;

    return ToolbarRegistryScope(
      registry: _registry,
      child: ToolbarChromeScope(
        nativeTopBarOwned: active,
        largeTitles: active && layout.largeTitles,
        topBarHidden: active && layout.barHidden,
        verticalTabs: active && layout.verticalTabs,
        largeTitleMargin: layout.titleMargin,
        child: widget.child,
      ),
    );
  }
}
