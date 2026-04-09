import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/card/card.dart';
import '../../models/remote_instance.dart';
import '../../providers/card_sender.dart';
import '../../services/notification_service.dart';
import '../app_layout.dart';
import '../components/card_detail/bottom_actions.dart';
import '../components/instances/select_instance_dialog.dart';
import '../components/reader/scanned_card_detail_v2.dart';
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

  void _copyValue(BuildContext context, WidgetRef ref) {
    Clipboard.setData(ClipboardData(text: card.value ?? ''));
    ref
        .read(notificationServiceProvider)
        .showSuccess(context.l10n.valueCopiedToClipboard);
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final senderState = ref.watch(cardSenderProvider);

    return Scaffold(
      appBar: layout.showPageAppBar ? _buildAppBar(context, ref) : null,
      body: SafeArea(
        top: !layout.showPageAppBar,
        bottom: false,
        child: _buildBody(context, ref, senderState),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Text(context.l10n.cardDetails(card.name)),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () => _copyValue(context, ref),
          tooltip: context.l10n.copyValue,
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    CardSenderState senderState,
  ) {
    return _CardDetailBody(
      detail: ScannedCardDetailV2(card: card, showHeader: true),
      actions: CardDetailBottomActions(
        onSend: () => _sendCard(context, ref),
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
