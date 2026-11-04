import 'package:flutter/widgets.dart';

/// How far, in points, a Liquid Glass control may draw past its own frame:
/// its rim highlight and the swell of a pressed control.
///
/// Flutter covers a platform view only inside its frame when a page slides
/// over it, so whatever the glass draws outside that frame shows through the
/// page on top. The native view is made this much larger on every side and
/// insets the control by the same amount, so the glass stays inside the frame
/// Flutter covers.
const double kGlassBleed = 6;

/// Lays out [child], a platform view hosting a Liquid Glass control, at the
/// size it is given and paints it [kGlassBleed] larger on every side. The
/// native view insets its control by [kGlassBleed] (the `bleed` creation
/// parameter). Touches in the margin fall through to the widgets underneath.
class GlassBleed extends StatelessWidget {
  const GlassBleed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -kGlassBleed,
          top: -kGlassBleed,
          right: -kGlassBleed,
          bottom: -kGlassBleed,
          child: child,
        ),
      ],
    );
  }
}
