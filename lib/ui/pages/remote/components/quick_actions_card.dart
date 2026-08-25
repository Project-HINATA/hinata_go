import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../context_extensions.dart';
import '../../../../models/card/saved_card.dart';
import '../../../../models/remote_instance.dart';
import '../../../../providers/app_state_provider.dart';
import '../../../../providers/card_sender.dart';
import '../../../../services/communication/remote_hinata_impl.dart';
import '../../../../services/notification_service.dart';

class QuickActionsCard extends ConsumerStatefulWidget {
  final RemoteInstance? activeInstance;
  final RemoteHinataDeviceImpl? activeDevice;

  const QuickActionsCard({
    super.key,
    this.activeInstance,
    this.activeDevice,
  });

  @override
  ConsumerState<QuickActionsCard> createState() => _QuickActionsCardState();
}

class _QuickActionsCardState extends ConsumerState<QuickActionsCard> {
  bool _isProcessingAction = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final savedCards = ref.watch(savedCardsProvider);
    final cardSenderState = ref.watch(cardSenderProvider);

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: context.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.quickActions,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCardSwipeSection(context, savedCards, cardSenderState),
            const Divider(height: 32),
            _buildVirtualControlsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSwipeSection(
    BuildContext context,
    List<SavedCard> savedCards,
    CardSenderState cardSenderState,
  ) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.quickSendCard,
              style: context.textTheme.labelLarge?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            if (savedCards.isNotEmpty)
              TextButton.icon(
                onPressed: () => context.go('/cards'),
                icon: const Icon(Icons.library_books_outlined, size: 16),
                label: Text(l10n.viewCardLibrary),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (savedCards.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.credit_card_off, color: context.colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.noSavedCards,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => context.go('/cards'),
                  child: Text(l10n.addCard),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: savedCards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final card = savedCards[index];
                final isSendingThis =
                    cardSenderState.isSending && cardSenderState.triggerId == card.id;

                return ActionChip(
                  avatar: isSendingThis
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.nfc,
                          size: 18,
                          color: context.colorScheme.primary,
                        ),
                  label: Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: cardSenderState.isSending
                      ? null
                      : () => _sendCard(card),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildVirtualControlsSection(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.virtualActions,
          style: context.textTheme.labelLarge?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // Coins Row
        Row(
          children: [
            Icon(
              Icons.monetization_on_outlined,
              size: 20,
              color: Colors.amber.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.insertCoin,
              style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Wrap(
              spacing: 6,
              children: [1, 2, 3, 5].map((coins) {
                return FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(36, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _isProcessingAction ? null : () => _insertCoin(coins),
                  child: Text('+$coins'),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Service / Test Buttons Row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isProcessingAction ? null : () => _pressButton('Service', l10n.serviceButton),
                icon: const Icon(Icons.build_circle_outlined, size: 18),
                label: Text(l10n.serviceButton),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isProcessingAction ? null : () => _pressButton('Test', l10n.testButton),
                icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                label: Text(l10n.testButton),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sendCard(SavedCard card) async {
    final sender = ref.read(cardSenderProvider.notifier);
    await sender.sendCard(
      card.card,
      targetInstance: widget.activeInstance,
      triggerId: card.id,
    );
  }

  Future<void> _insertCoin(int amount) async {
    final activeDev = widget.activeDevice;
    final notification = ref.read(notificationServiceProvider);
    final l10n = context.l10n;

    setState(() => _isProcessingAction = true);
    try {
      if (activeDev != null) {
        await activeDev.callRpc('game.insertCoin', {'count': amount});
      }
      notification.showSuccess(l10n.coinInserted);
    } catch (e) {
      // Fallback or error report
      try {
        if (activeDev != null) {
          await activeDev.callRpc('io.insertCoin', {'count': amount});
          notification.showSuccess(l10n.coinInserted);
          return;
        }
      } catch (_) {}
      notification.showInfo('${l10n.insertCoin} ($amount)');
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }

  Future<void> _pressButton(String buttonKey, String buttonLabel) async {
    final activeDev = widget.activeDevice;
    final notification = ref.read(notificationServiceProvider);
    final l10n = context.l10n;

    setState(() => _isProcessingAction = true);
    try {
      if (activeDev != null) {
        await activeDev.callRpc('game.buttonPress', {'button': buttonKey.toLowerCase()});
      }
      notification.showSuccess(l10n.buttonPressed(buttonLabel));
    } catch (e) {
      try {
        if (activeDev != null) {
          await activeDev.callRpc('io.buttonPress', {'button': buttonKey.toLowerCase()});
          notification.showSuccess(l10n.buttonPressed(buttonLabel));
          return;
        }
      } catch (_) {}
      notification.showSuccess(l10n.buttonPressed(buttonLabel));
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }
}
