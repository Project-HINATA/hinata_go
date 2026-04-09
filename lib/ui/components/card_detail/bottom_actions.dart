import 'package:flutter/material.dart';
import 'package:hinata_go/context_extensions.dart';

class CardDetailBottomActions extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback onSave;
  final bool isSending;
  final bool isSaving;

  const CardDetailBottomActions({
    super.key,
    required this.onSend,
    required this.onSave,
    required this.isSending,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final padding = context.mediaQuery.padding;

    return Container(
      padding: _buildPadding(padding),
      decoration: _buildDecoration(colorScheme),
      child: Row(
        children: [
          _buildSaveButton(context, colorScheme),
          const SizedBox(width: 12),
          _buildSendButton(context, colorScheme),
        ],
      ),
    );
  }

  EdgeInsets _buildPadding(EdgeInsets padding) {
    return EdgeInsets.only(
      left: 24,
      right: 24,
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
        onPressed: isSaving || isSending ? null : onSave,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSaving ? _buildSpinner() : const Icon(Icons.folder_special),
        label: Text(
          isSaving ? context.l10n.savingUpper : context.l10n.saveUpper,
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context, ColorScheme colorScheme) {
    return Expanded(
      flex: 2,
      child: FilledButton.icon(
        onPressed: isSending || isSaving ? null : onSend,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSending
            ? _buildSpinner(color: Colors.white)
            : const Icon(Icons.send),
        label: Text(
          isSending ? context.l10n.sendingUpper : context.l10n.sendUpper,
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
