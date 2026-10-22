import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/engine/mifare_write_payload.dart';
import '../../l10n/l10n.dart';
import '../../models/card/card.dart';
import '../../models/card/ndef.dart';
import '../components/saved_cards/ndef_editor_dialog.dart';
import '../../models/card/transit.dart';
import '../../models/card/saved_card.dart';
import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/card_sender.dart';
import '../../providers/card_writer_provider.dart';
import '../../services/notification_service.dart';
import '../components/card_detail/bottom_actions.dart';
import '../components/card_detail/write_card_dialog.dart';
import '../components/instances/select_instance_dialog.dart';
import '../components/reader/scanned_card_detail_v2.dart';
import '../components/reader/transit_history_card.dart';
import '../components/reader/ndef_records_card.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/native_alert.dart';
import '../widgets/save_card_dialog.dart';

class CardDetailPage extends HookConsumerWidget {
  final SavedCard? savedCard;
  final ICCard? card;

  const CardDetailPage({super.key, this.savedCard, this.card})
    : assert(savedCard != null || card != null);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _saveCard(
    BuildContext context,
    ICCard activeCard, {
    String? initialName,
  }) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => SaveCardDialog(
        card: activeCard,
        source: 'Saved',
        initialName: initialName,
      ),
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
    final newName = useCupertinoChrome
        ? (await showNativeTextInput(
            context,
            title: l10n.renameCard,
            placeholder: l10n.cardNameLabel,
            initialValue: activeSavedCard.name,
            confirmLabel: l10n.save,
          ))?.trim()
        : await showDialog<String>(
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
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
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
      ref.read(notificationServiceProvider).showSuccess(l10n.renameSuccess);
    }
  }

  Future<void> _deleteCard(
    BuildContext context,
    WidgetRef ref,
    SavedCard activeSavedCard,
  ) async {
    final confirm = useCupertinoChrome
        ? await showNativeConfirmation(
            context,
            title: l10n.deleteCard,
            message: l10n.confirmDeleteCard,
            confirmLabel: l10n.delete,
            destructive: true,
          )
        : await showDialog<bool>(
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          );

    if (confirm == true) {
      if (!context.mounted) return;
      ref.read(savedCardsProvider.notifier).removeCard(activeSavedCard.id);
      ref.read(notificationServiceProvider).showSuccess(l10n.deleteSuccess);
      Navigator.pop(context); // Pop back out of detail page
    }
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderState = ref.watch(cardSenderProvider);
    final writerState = ref.watch(cardWriterProvider);
    final writerAvailable = ref.watch(cardWriterAvailableProvider);
    final ndefWriterAvailable = ref.watch(ndefWriterAvailableProvider);
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

    return AppScaffold(
      title: activeCard is NdefCard
          ? l10n.ndefDetails
          : l10n.cardDetails(activeSavedCard?.name ?? activeCard.name),
      actions: activeSavedCard == null || writerState.isWriting
          ? const []
          : _buildActions(context, ref, activeSavedCard, activeCard),
      // The detail scrolls under the native iOS bar and its glass, padding
      // itself below the bar; a Material app bar takes the top inset away.
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(
          context,
          ref,
          senderState,
          writerState,
          (activeSavedCard?.card ?? card) is NdefCard
              ? ndefWriterAvailable
              : writerAvailable,
          activeSavedCard,
          activeCard,
        ),
      ),
    );
  }

  List<AdaptiveAppBarAction> _buildActions(
    BuildContext context,
    WidgetRef ref,
    SavedCard activeSavedCard,
    ICCard activeCard,
  ) {
    return [
      if (activeCard is NdefCard)
        AdaptiveAppBarAction(
          iosSymbol: 'square.and.pencil',
          icon: Icons.edit_outlined,
          label: l10n.ndefEdit,
          onPressed: () => showNdefEditor(
            context,
            initialFolderId: activeSavedCard.folderId,
            savedCard: activeSavedCard,
          ),
        )
      else
        AdaptiveAppBarAction(
          iosSymbol: 'pencil',
          icon: Icons.edit_note,
          label: l10n.renameCard,
          onPressed: () => _renameCard(context, ref, activeSavedCard),
        ),
      AdaptiveAppBarAction(
        iosSymbol: 'trash',
        icon: Icons.delete_outline,
        label: l10n.deleteCard,
        onPressed: () => _deleteCard(context, ref, activeSavedCard),
      ),
    ];
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    CardSenderState senderState,
    CardWriterState writerState,
    bool writerAvailable,
    SavedCard? activeSavedCard,
    ICCard activeCard,
  ) {
    final canWrite =
        activeSavedCard != null &&
        writerAvailable &&
        (activeCard is NdefCard || MifareCardWritePayload.canBuild(activeCard));
    final canSend = activeCard.gamePayload != null;
    // The actions' height comes from the width they will get and the buttons
    // they will show, so the detail can reserve it in the same layout pass.
    final media = MediaQuery.of(context);
    final actionsHeight = CardDetailBottomActions.heightFor(
      width: media.size.width - 32,
      padding: media.padding,
      hasWrite: canWrite,
      hasSend: canSend,
    );

    return _CardDetailBody(
      actionsHeight: actionsHeight,
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScannedCardDetailV2(
            card: activeCard,
            title: activeSavedCard?.name,
            showHeader: true,
          ),
          if (activeCard is NdefCard) ...[
            const SizedBox(height: 16),
            NdefRecordsCard(card: activeCard),
          ],
          if (activeCard is TransitCard) ...[
            const SizedBox(height: 16),
            TransitHistoryCard(card: activeCard),
          ],
        ],
      ),
      actions: CardDetailBottomActions(
        onSend: canSend ? () => _sendCard(context, ref, activeCard) : null,
        onSave: () => _saveCard(
          context,
          activeCard,
          initialName: activeCard is NdefCard ? activeSavedCard?.name : null,
        ),
        saveLabel: activeCard is NdefCard && activeSavedCard != null
            ? l10n.ndefSaveCopy
            : null,
        onWrite: canWrite
            ? () => showCardWriteFlow(context, ref, activeSavedCard)
            : null,
        isSending: senderState.isSending,
        isSaving: false,
        isWriting: writerState.isWriting,
      ),
    );
  }
}

/// The card detail with its actions floating over the bottom of it. The detail
/// scrolls underneath them, and keeps room to scroll its end clear of them.
class _CardDetailBody extends StatelessWidget {
  const _CardDetailBody({
    required this.detail,
    required this.actions,
    required this.actionsHeight,
  });

  final Widget detail;
  final Widget actions;

  /// The height the actions take, decided by the page from the same values
  /// that lay them out. Measuring it after layout instead would read the
  /// geometry of a page that is still sliding in, and rebuild the detail.
  final double actionsHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20 + MediaQuery.paddingOf(context).top,
              20,
              20 + actionsHeight,
            ),
            child: detail,
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: actions),
      ],
    );
  }
}
