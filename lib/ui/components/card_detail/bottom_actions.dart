import 'package:flutter/material.dart';
import 'package:hinata_go/context_extensions.dart';

class CardDetailBottomActions extends StatelessWidget {
  final VoidCallback? onSend;
  final VoidCallback onSave;
  final VoidCallback? onWrite;
  final bool isSending;
  final bool isSaving;
  final bool isWriting;

  const CardDetailBottomActions({
    super.key,
    this.onSend,
    required this.onSave,
    this.onWrite,
    required this.isSending,
    required this.isSaving,
    this.isWriting = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final padding = context.mediaQuery.padding;

    return Container(
      padding: _buildPadding(padding),
      decoration: _buildDecoration(colorScheme),
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

  BoxDecoration _buildDecoration(ColorScheme colorScheme) {
    return BoxDecoration(
      color: colorScheme.surface,
      boxShadow: [
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, -5),
        ),
      ],
    );
  }

  Widget _buildSaveButton(BuildContext context, ColorScheme colorScheme) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: isSaving || isSending || isWriting ? null : onSave,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSaving ? _buildSpinner() : const Icon(Icons.folder_special),
        label: Text(isSaving ? l10n.savingUpper : l10n.saveUpper),
      ),
    );
  }

  Widget _buildWriteButton(BuildContext context) {
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

  Widget _buildSpinner({Color? color}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
