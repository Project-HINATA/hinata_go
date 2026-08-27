import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:go_router/go_router.dart';

import '../../../models/card/saved_card.dart';
import '../../../providers/app_state_provider.dart';
import '../../../providers/card_sender.dart';

class CardItem extends ConsumerWidget {
  final SavedCard card;
  final Future<void> Function(SavedCard card) onSend;

  const CardItem({super.key, required this.card, required this.onSend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final senderState = ref.watch(cardSenderProvider);
    final isThisCardSending =
        senderState.isSending && senderState.triggerId == card.id;
    final isAnyCardSending = senderState.isSending;

    return Dismissible(
      key: ValueKey(card.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) {
        ref.read(savedCardsProvider.notifier).removeCard(card.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
          child: card.card.logoPath != null
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SvgPicture.asset(
                    card.card.logoPath!,
                    colorFilter: ColorFilter.mode(
                      colorScheme.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                )
              : Icon(Icons.credit_card, color: colorScheme.primary),
        ),
        title: Text(
          card.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (card.card.tags.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  card.card.tags.first.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Text(
                card.showValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
        trailing: card.card.gamePayload == null
            ? null
            : isThisCardSending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.send_rounded),
                onPressed: isAnyCardSending ? null : () => onSend(card),
                tooltip: l10n.quickSend,
                color: isAnyCardSending ? colorScheme.outline : null,
              ),
        onTap: () => context.push('/card_detail', extra: card),
      ),
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}
