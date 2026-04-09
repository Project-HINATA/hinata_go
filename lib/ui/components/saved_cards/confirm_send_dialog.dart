import 'package:flutter/material.dart';
import '../../../models/card/saved_card.dart';
import '../../../l10n/l10n.dart';

class ConfirmSendDialog extends StatelessWidget {
  final SavedCard card;

  const ConfirmSendDialog({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.confirmSend),
      content: Text(context.l10n.confirmSendWithValue(card.showValue)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.send),
        ),
      ],
    );
  }
}
