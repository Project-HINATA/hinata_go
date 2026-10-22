import 'package:flutter/widgets.dart';

/// Tells the pages below an [AdaptiveToolbarHost] how the native UIKit chrome
/// above them is laid out, so they lay themselves out for it.
///
/// The native shell decides all of it from the system's own traits and the
/// host only passes it on: a page never measures the device to agree with it.
class ToolbarChromeScope extends InheritedWidget {
  const ToolbarChromeScope({
    super.key,
    this.nativeTopBarOwned = false,
    this.largeTitles = false,
    this.topBarHidden = false,
    this.verticalTabs = false,
    this.largeTitleMargin,
    required super.child,
  });

  /// True while a native UIKit `UINavigationController` above the Flutter view
  /// owns the top bar. Pages draw no top bar and add no top inset; the native
  /// controller contributes the safe area instead.
  final bool nativeTopBarOwned;

  /// True where pages draw their own large title, which the native bar
  /// collapses into its small title, and a chip strip under the bar: where
  /// the tab bar sits at the bottom of a compact-width window.
  final bool largeTitles;

  /// True while the native shell hides the top bar (an iPhone in landscape):
  /// pages that still need their controls show them themselves.
  final bool topBarHidden;

  /// True while the tabs run down a vertical bar (iPhone Duo), so switching
  /// tabs moves along that axis.
  final bool verticalTabs;

  /// The leading margin of the native bar's own title, which a large title
  /// lines up with. Null until the native shell reports it.
  final double? largeTitleMargin;

  /// The nearest scope, or null when no host is installed and the page must
  /// draw its whole toolbar itself.
  static ToolbarChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarChromeScope>();

  @override
  bool updateShouldNotify(ToolbarChromeScope oldWidget) =>
      nativeTopBarOwned != oldWidget.nativeTopBarOwned ||
      largeTitles != oldWidget.largeTitles ||
      topBarHidden != oldWidget.topBarHidden ||
      verticalTabs != oldWidget.verticalTabs ||
      largeTitleMargin != oldWidget.largeTitleMargin;
}
