import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/card/card.dart';
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
  final SavedCard? savedCard;
  final ICCard? card;

  const CardDetailPage({super.key, this.savedCard, this.card})
    : assert(savedCard != null || card != null);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _saveCard(BuildContext context, ICCard activeCard) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => SaveCardDialog(card: activeCard, source: 'Saved'),
    );
  }

  Future<void> _sendCard(
    BuildContext context,
    WidgetRef ref,
    ICCard activeCard,
  ) async {
    final selectedInstance = await showDialog<RemoteInstance>(
      context: context,
      builder: (context) => const SelectInstanceDialog(),
    );
    if (selectedInstance == null) return;

    await ref
        .read(cardSenderProvider.notifier)
        .sendCard(activeCard, targetInstance: selectedInstance);
  }

  Future<void> _renameCard(
    BuildContext context,
    WidgetRef ref,
    SavedCard activeSavedCard,
  ) async {
    final controller = TextEditingController(text: activeSavedCard.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameCard),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.cardNameLabel),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != activeSavedCard.name) {
      if (!context.mounted) return;
      final updatedCard = activeSavedCard.copyWith(name: newName);
      ref.read(savedCardsProvider.notifier).updateCard(updatedCard);
      ref
          .read(notificationServiceProvider)
          .showSuccess(l10n.renameSuccess);
    }
  }

  Future<void> _deleteCard(
    BuildContext context,
    WidgetRef ref,
    SavedCard activeSavedCard,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteCard),
        content: Text(l10n.confirmDeleteCard),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      ref.read(savedCardsProvider.notifier).removeCard(activeSavedCard.id);
      ref
          .read(notificationServiceProvider)
          .showSuccess(l10n.deleteSuccess);
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

    SavedCard? activeSavedCard;
    if (savedCard != null) {
      activeSavedCard =
          savedCards.where((c) => c.id == savedCard!.id).firstOrNull ??
          savedCard;
    } else if (card != null) {
      try {
        activeSavedCard = savedCards.firstWhere(
          (c) => c.card.isSameCard(card!),
        );
      } catch (_) {
        activeSavedCard = null;
      }
    }

    final activeCard = activeSavedCard?.card ?? card!;

    return Scaffold(
      appBar: _buildAppBar(context, ref, activeSavedCard, activeCard),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(
          context,
          ref,
          senderState,
          activeSavedCard,
          activeCard,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    SavedCard? activeSavedCard,
    ICCard activeCard,
  ) {
    return AppBar(
      title: Text(
        l10n.cardDetails(activeSavedCard?.name ?? activeCard.name),
      ),
      actions: [
        if (activeSavedCard != null) ...[
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: () => _renameCard(context, ref, activeSavedCard),
            tooltip: l10n.renameCard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteCard(context, ref, activeSavedCard),
            tooltip: l10n.deleteCard,
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    CardSenderState senderState,
    SavedCard? activeSavedCard,
    ICCard activeCard,
  ) {
    return _CardDetailBody(
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScannedCardDetailV2(
            card: activeCard,
            title: activeSavedCard?.name,
            showHeader: true,
          ),
          if (activeCard is TransitCard) ...[
            const SizedBox(height: 16),
            TransitHistoryCard(card: activeCard),
          ],
        ],
      ),
      actions: CardDetailBottomActions(
        onSend: activeCard.gamePayload != null
            ? () => _sendCard(context, ref, activeCard)
            : null,
        onSave: () => _saveCard(context, activeCard),
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
