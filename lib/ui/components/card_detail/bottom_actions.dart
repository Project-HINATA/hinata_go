import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../widgets/app_scaffold.dart';

class CardDetailBottomActions extends StatelessWidget {
  final VoidCallback? onSend;
  final VoidCallback onSave;
  final String? saveLabel;
  final VoidCallback? onWrite;
  final bool isSending;
  final bool isSaving;
  final bool isWriting;

  const CardDetailBottomActions({
    super.key,
    this.onSend,
    required this.onSave,
    this.saveLabel,
    this.onWrite,
    required this.isSending,
    required this.isSaving,
    this.isWriting = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final padding = context.mediaQuery.padding;

    return Padding(
      padding: _buildPadding(padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useTwoRows =
              onWrite != null && onSend != null && constraints.maxWidth < 388;
          if (useTwoRows) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildSaveButton(context, colorScheme),
                    const SizedBox(width: 8),
                    _buildWriteButton(context),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [_buildSendButton(context, colorScheme)]),
              ],
            );
          }

          return Row(
            children: [
              _buildSaveButton(context, colorScheme),
              if (onWrite != null) ...[
                const SizedBox(width: 8),
                _buildWriteButton(context),
              ],
              if (onSend != null) ...[
                const SizedBox(width: 8),
                _buildSendButton(context, colorScheme),
              ],
            ],
          );
        },
      ),
    );
  }

  EdgeInsets _buildPadding(EdgeInsets padding) {
    return EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: padding.bottom > 0 ? padding.bottom : 24,
    );
  }

  Widget _buildSaveButton(BuildContext context, ColorScheme colorScheme) {
    if (useCupertinoChrome) {
      return Expanded(
        child: _nativeButton(
          context,
          label: isSaving ? l10n.savingUpper : (saveLabel ?? l10n.saveUpper),
          icon: CupertinoIcons.folder_badge_plus,
          style: AdaptiveButtonStyle.glass,
          onPressed: isSaving || isSending || isWriting ? null : onSave,
          busy: isSaving,
        ),
      );
    }
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: isSaving || isSending || isWriting ? null : onSave,
        style: OutlinedButton.styleFrom(
          // Floats over the scrolling detail, so it needs a fill of its own.
          backgroundColor: colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSaving ? _buildSpinner() : const Icon(Icons.folder_special),
        label: Text(
          isSaving ? l10n.savingUpper : (saveLabel ?? l10n.saveUpper),
        ),
      ),
    );
  }

  Widget _buildWriteButton(BuildContext context) {
    if (useCupertinoChrome) {
      return Expanded(
        child: _nativeButton(
          context,
          label: l10n.cardWrite,
          icon: CupertinoIcons.waveform_path_ecg,
          style: AdaptiveButtonStyle.glass,
          onPressed: isSaving || isSending || isWriting ? null : onWrite,
          busy: isWriting,
        ),
      );
    }
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: isSaving || isSending || isWriting ? null : onWrite,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isWriting ? _buildSpinner() : const Icon(Icons.nfc),
        label: Text(l10n.cardWrite),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context, ColorScheme colorScheme) {
    if (useCupertinoChrome) {
      return Expanded(
        child: _nativeButton(
          context,
          label: isSending ? l10n.sendingUpper : l10n.sendUpper,
          icon: CupertinoIcons.paperplane_fill,
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: isSending || isSaving || isWriting ? null : onSend,
          busy: isSending,
        ),
      );
    }
    return Expanded(
      child: FilledButton.icon(
        onPressed: isSending || isSaving || isWriting ? null : onSend,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSending
            ? _buildSpinner(color: Colors.white)
            : const Icon(Icons.send),
        label: Text(isSending ? l10n.sendingUpper : l10n.sendUpper),
      ),
    );
  }

  /// A native iOS button: a Liquid Glass pill on iOS 26+, a tinted capsule
  /// before that. The label and icon are drawn by Flutter over the native
  /// button so they keep the app's language and symbols.
  Widget _nativeButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required AdaptiveButtonStyle style,
    required VoidCallback? onPressed,
    required bool busy,
  }) {
    final scheme = context.colorScheme;
    final foreground =
        style == AdaptiveButtonStyle.prominentGlass ||
            style == AdaptiveButtonStyle.filled
        ? scheme.onPrimary
        : scheme.primary;
    return SizedBox(
      height: 56,
      child: AdaptiveButton.child(
        onPressed: onPressed ?? () {},
        style: style,
        size: AdaptiveButtonSize.large,
        enabled: onPressed != null,
        useSmoothRectangleBorder: false,
        color:
            style == AdaptiveButtonStyle.prominentGlass ||
                style == AdaptiveButtonStyle.filled
            ? scheme.primary
            : null,
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
      ),
    );
  }

  Widget _buildSpinner({Color? color}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
