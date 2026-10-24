import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../models/card/saved_card.dart';
import '../../../providers/card_emulator_provider.dart';

Future<void> showCardEmulateFlow(
  BuildContext context,
  WidgetRef ref,
  SavedCard card,
) async {
  final emulator = ref.read(cardEmulatorProvider.notifier);
  unawaited(emulator.emulate(card));
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _EmulateDialog(),
  );
  // The dialog may leave with its route, not through its stop button.
  await emulator.stop();
}

class _EmulateDialog extends ConsumerWidget {
  const _EmulateDialog();

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    await ref.read(cardEmulatorProvider.notifier).stop();
    if (!context.mounted) return;
    if (ref.read(cardEmulatorProvider).status == CardEmulatorStatus.stopped) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emulator = ref.watch(cardEmulatorProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !emulator.isEmulating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop(context, ref));
      },
      child: AlertDialog(
        title: Text(l10n.ndefEmulateTitle),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _StatusIndicator(status: emulator.status),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_statusText(emulator)),
                          if (emulator.readCount > 0)
                            Text(
                              l10n.ndefEmulateReadCount(emulator.readCount),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colorScheme.primary),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _InfoRow(text: l10n.ndefEmulateReadOnly),
                _InfoRow(text: l10n.ndefEmulatePollingPaused),
                _InfoRow(text: l10n.ndefEmulateIosLimit),
                _InfoRow(text: l10n.ndefEmulateFirmware),
              ],
            ),
          ),
        ),
        actions: [
          if (emulator.isEmulating)
            FilledButton.tonal(
              onPressed: emulator.canStop ? () => _stop(context, ref) : null,
              child: Text(
                emulator.canStop
                    ? l10n.ndefEmulateStop
                    : l10n.ndefEmulateStopping,
              ),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cardWriteDone),
            ),
        ],
      ),
    );
  }

  String _statusText(CardEmulatorState state) => switch (state.status) {
    CardEmulatorStatus.idle ||
    CardEmulatorStatus.starting => l10n.ndefEmulatePreparing,
    CardEmulatorStatus.waitingForPhone => l10n.ndefEmulateWaiting,
    CardEmulatorStatus.phoneConnected => l10n.ndefEmulateConnected,
    CardEmulatorStatus.stopping => l10n.ndefEmulateStopping,
    CardEmulatorStatus.stopped => l10n.ndefEmulateStopped,
    CardEmulatorStatus.failed => switch (state.failure) {
      CardEmulatorFailure.noReader => l10n.ndefEmulateNoReader,
      CardEmulatorFailure.unsupportedCard => l10n.ndefEmulateUnsupported,
      CardEmulatorFailure.readerDisconnected =>
        l10n.ndefEmulateReaderDisconnected,
      CardEmulatorFailure.failed || null => l10n.ndefEmulateFailed,
    },
  };
}

class _StatusIndicator extends StatelessWidget {
  final CardEmulatorStatus status;

  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 30,
      child: switch (status) {
        CardEmulatorStatus.phoneConnected => Icon(
          Icons.contactless,
          size: 30,
          color: colorScheme.primary,
        ),
        CardEmulatorStatus.stopped => Icon(
          Icons.check_circle_outline,
          size: 30,
          color: colorScheme.primary,
        ),
        CardEmulatorStatus.failed => Icon(
          Icons.error_outline,
          size: 30,
          color: colorScheme.error,
        ),
        _ => const Padding(
          padding: EdgeInsets.all(1),
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String text;

  const _InfoRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
