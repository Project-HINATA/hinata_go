import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// A full-width native action button with a symbol and a label, as on the
/// card detail and in the NDEF editor.
///
/// On iOS 26 and later the symbol, label and activity indicator are drawn by
/// the native Liquid Glass button itself. Flutter draws nothing over the
/// platform view, so it needs no overlay layer, which keeps page transitions
/// over and under these buttons smooth. Earlier iOS versions draw [icon] and
/// the label in Flutter over a tinted native capsule.
class GlassLabelButton extends StatelessWidget {
  const GlassLabelButton({
    super.key,
    required this.label,
    required this.icon,
    required this.sfSymbol,
    required this.style,
    required this.onPressed,
    this.busy = false,
  });

  final String label;

  /// The symbol Flutter draws before iOS 26.
  final IconData icon;

  /// The SF Symbol the native button draws on iOS 26 and later.
  final String sfSymbol;

  final AdaptiveButtonStyle style;

  /// Disables the button when null.
  final VoidCallback? onPressed;

  /// Shows an activity indicator in place of the symbol.
  final bool busy;

  bool get _prominent =>
      style == AdaptiveButtonStyle.prominentGlass ||
      style == AdaptiveButtonStyle.filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = _prominent ? scheme.onPrimary : scheme.primary;
    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26Button.labeled(
        onPressed: onPressed ?? () {},
        label: label,
        sfSymbol: SFSymbol(sfSymbol, size: 15),
        busy: busy,
        fontSize: 16,
        style: _prominent
            ? IOS26ButtonStyle.prominentGlass
            : IOS26ButtonStyle.glass,
        size: IOS26ButtonSize.large,
        enabled: onPressed != null,
        useSmoothRectangleBorder: false,
        color: _prominent ? scheme.primary : null,
        textColor: foreground,
      );
    }
    return AdaptiveButton.child(
      onPressed: onPressed ?? () {},
      style: style,
      size: AdaptiveButtonSize.large,
      enabled: onPressed != null,
      useSmoothRectangleBorder: false,
      color: _prominent ? scheme.primary : null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else
            Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
