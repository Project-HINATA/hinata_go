import 'package:flutter/widgets.dart';

/// Height of the band a large title takes below the native bar: the
/// difference between UIKit's expanded large-title bar and its inline bar.
const double kLargeTitleHeight = 52.0;

/// How far a page scrolls before the top of its large title reaches the bar.
/// From there the bar shows its glass and small title, and the large title
/// fades out, so the glass never covers half of it. The title's text box
/// starts 5pt below the bar; Latin capitals start 13pt below it and Chinese
/// glyphs 7.5pt.
const double kLargeTitleCollapseOffset = 8;

/// Height of the strip of Liquid Glass chips the native bar shows under
/// itself for [AdaptiveAppBar.chips].
const double kTopBarAccessoryHeight = 52.0;

/// One chip of the strip the native top bar shows under itself, such as a
/// folder or a filter.
@immutable
class AdaptiveToolbarChip {
  const AdaptiveToolbarChip({
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.onLongPress,
  });

  final String label;

  /// Drawn as the prominent (tinted) glass chip.
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
}

/// Tells a page whether the native top bar shows its
/// [AdaptiveAppBar.chips] as a strip under the bar.
///
/// The page's top padding then already includes the strip, and the page
/// must not draw a selector of its own. Where the scope is absent (Material,
/// landscape, the iPhone Duo vertical bar, iOS before 26) the page draws the
/// chips itself.
class TopBarAccessoryScope extends InheritedWidget {
  const TopBarAccessoryScope({super.key, required super.child});

  static bool isNative(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopBarAccessoryScope>() !=
      null;

  @override
  bool updateShouldNotify(TopBarAccessoryScope oldWidget) => false;
}
