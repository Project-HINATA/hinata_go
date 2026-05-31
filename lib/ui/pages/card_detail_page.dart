import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/card/card.dart';
import '../../models/card/invalid_mifare.dart';
import '../../models/card/transit.dart';
import '../../models/card/saved_card.dart';
import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/card_sender.dart';
import '../../services/notification_service.dart';
import '../components/card_detail/bottom_actions.dart';
import '../components/instances/select_instance_dialog.dart';
import '../components/reader/scanned_card_detail_v2.dart';
import '../components/reader/transit_history_card.dart';
import '../widgets/save_card_dialog.dart';

class CardDetailPage extends HookConsumerWidget {
  final ICCard card;

  const CardDetailPage({super.key, required this.card});

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _saveCard(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => SaveCardDialog(card: card, source: 'Saved'),
    );
  }

  Future<void> _sendCard(BuildContext context, WidgetRef ref) async {
    final selectedInstance = await showDialog<RemoteInstance>(
      context: context,
      builder: (context) => const SelectInstanceDialog(),
    );
    if (selectedInstance == null) return;

    await ref
        .read(cardSenderProvider.notifier)
        .sendCard(card, targetInstance: selectedInstance);
  }

  Future<void> _renameCard(
    BuildContext context,
    WidgetRef ref,
    SavedCard savedCard,
  ) async {
    final controller = TextEditingController(text: savedCard.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.renameCard),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: context.l10n.cardNameLabel),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != savedCard.name) {
      if (!context.mounted) return;
      final updatedCard = savedCard.copyWith(name: newName);
      ref.read(savedCardsProvider.notifier).updateCard(updatedCard);
      ref
          .read(notificationServiceProvider)
          .showSuccess(context.l10n.renameSuccess);
    }
  }

  Future<void> _deleteCard(
    BuildContext context,
    WidgetRef ref,
    SavedCard savedCard,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteCard),
        content: Text(context.l10n.confirmDeleteCard),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      ref.read(savedCardsProvider.notifier).removeCard(savedCard.id);
      ref
          .read(notificationServiceProvider)
          .showSuccess(context.l10n.deleteSuccess);
      Navigator.pop(context); // Pop back out of detail page
    }
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderState = ref.watch(cardSenderProvider);
    final savedCards = ref.watch(savedCardsProvider);
    SavedCard? savedCard;
    try {
      savedCard = savedCards.firstWhere((c) => c.card.isSameCard(card));
    } catch (_) {
      savedCard = null;
    }

    return Scaffold(
      appBar: _buildAppBar(context, ref, savedCard),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(context, ref, senderState),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    SavedCard? savedCard,
  ) {
    return AppBar(
      title: Text(context.l10n.cardDetails(savedCard?.name ?? card.name)),
      actions: [
        if (savedCard != null) ...[
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: () => _renameCard(context, ref, savedCard),
            tooltip: context.l10n.renameCard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteCard(context, ref, savedCard),
            tooltip: context.l10n.deleteCard,
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    CardSenderState senderState,
  ) {
    return _CardDetailBody(
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScannedCardDetailV2(card: card, showHeader: true),
          if (card is TransitCard) ...[
            const SizedBox(height: 16),
            TransitHistoryCard(card: card as TransitCard),
          ],
        ],
      ),
      actions: card is InvalidMifareCard
          ? const SizedBox.shrink()
          : CardDetailBottomActions(
              onSend: card.gamePayload != null
                  ? () => _sendCard(context, ref)
                  : null,
              onSave: () => _saveCard(context),
              isSending: senderState.isSending,
              isSaving: false,
            ),
    );
  }
}

class _CardDetailBody extends StatelessWidget {
  const _CardDetailBody({required this.detail, required this.actions});

  final Widget detail;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: detail,
          ),
        ),
        actions,
      ],
    );
  }
}
