import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/engine/mifare_write_payload.dart';
import '../../../l10n/l10n.dart';
import '../../../models/card/saved_card.dart';
import '../../../models/card/ndef.dart';
import '../../../providers/card_writer_provider.dart';
import '../../../services/nfc/mifare_card_writer.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/native_alert.dart';

Future<void> showCardWriteFlow(
  BuildContext context,
  WidgetRef ref,
  SavedCard card,
) async {
  final isNdef = card.card is NdefCard;
  final mode = isNdef
      ? (await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.ndefWriteTitle),
                    content: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _WarningRow(text: l10n.ndefWriteOverwrite),
                            _WarningRow(text: l10n.ndefWriteClassicWarning),
                            _WarningRow(text: l10n.ndefWriteKeepTag),
                            if (defaultTargetPlatform == TargetPlatform.iOS)
                              _WarningRow(text: l10n.ndefWriteIosLimit),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(l10n.cardWriteStart),
                      ),
                    ],
                  ),
                ) ==
                true
            ? CardWriteMode.rewritable
            : null)
      : await showDialog<CardWriteMode>(
          context: context,
          builder: (context) => const _WriteOptionsDialog(),
        );
  if (mode == null || !context.mounted) return;

  if (mode == CardWriteMode.permanentlyReadOnly) {
    final confirmed = useCupertinoChrome
        ? await showNativeConfirmation(
            context,
            title: l10n.cardWritePermanentConfirmTitle,
            message: l10n.cardWritePermanentConfirmBody,
            confirmLabel: l10n.cardWriteConfirmPermanent,
            destructive: true,
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: Icon(
                Icons.lock_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.cardWritePermanentConfirmTitle),
              content: Text(l10n.cardWritePermanentConfirmBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(l10n.cardWriteConfirmPermanent),
                ),
              ],
            ),
          );
    if (confirmed != true || !context.mounted) return;
  }

  ref.read(cardWriterProvider.notifier).reset();
  final operation = ref.read(cardWriterProvider.notifier).writeCard(card, mode);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _WriteProgressDialog(operation: operation, isNdef: isNdef),
  );
}

class _WriteOptionsDialog extends HookWidget {
  const _WriteOptionsDialog();

  @override
  Widget build(BuildContext context) {
    final mode = useState(CardWriteMode.rewritable);
    return AlertDialog(
      title: Text(l10n.cardWriteTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WarningRow(text: l10n.cardWriteWarningWritable),
              _WarningRow(text: l10n.cardWriteWarningUid),
              _WarningRow(text: l10n.cardWriteWarningCompatibility),
              const SizedBox(height: 20),
              Text(
                l10n.cardWriteMode,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<CardWriteMode>(
                segments: [
                  ButtonSegment(
                    value: CardWriteMode.rewritable,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.cardWriteRewritable),
                  ),
                  ButtonSegment(
                    value: CardWriteMode.permanentlyReadOnly,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(l10n.cardWritePermanent),
                  ),
                ],
                selected: {mode.value},
                onSelectionChanged: (selection) => mode.value = selection.first,
              ),
              const SizedBox(height: 8),
              Text(
                mode.value == CardWriteMode.rewritable
                    ? l10n.cardWriteRewritableDescription
                    : l10n.cardWritePermanentDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, mode.value),
          icon: const Icon(Icons.nfc),
          label: Text(l10n.cardWriteStart),
        ),
      ],
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String text;

  const _WarningRow({required this.text});

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

class _WriteProgressDialog extends ConsumerWidget {
  final Future<bool> operation;
  final bool isNdef;

  const _WriteProgressDialog({required this.operation, required this.isNdef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final writer = ref.watch(cardWriterProvider);
    return PopScope(
      canPop: !writer.isWriting,
      child: AlertDialog(
        title: Text(isNdef ? l10n.ndefWriteTitle : l10n.cardWriteTitle),
        content: SizedBox(
          width: 400,
          child: FutureBuilder<bool>(
            future: operation,
            builder: (context, snapshot) {
              final finished = snapshot.connectionState == ConnectionState.done;
              final success = finished && snapshot.data == true;
              return Row(
                children: [
                  if (!finished)
                    const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    Icon(
                      success
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 30,
                      color: success
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      finished
                          ? (success
                                ? (isNdef
                                      ? l10n.ndefWriteSuccess
                                      : l10n.cardWriteSuccess)
                                : _failureText(writer.failure))
                          : _progressText(writer),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          if (writer.canCancel)
            TextButton(
              onPressed: () => ref.read(cardWriterProvider.notifier).cancel(),
              child: Text(l10n.cancel),
            ),
          FutureBuilder<bool>(
            future: operation,
            builder: (context, snapshot) =>
                snapshot.connectionState == ConnectionState.done
                ? FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cardWriteDone),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _progressText(CardWriterState state) {
    if (state.status == CardWriterStatus.waitingForCard) {
      return l10n.cardWriteWaitingForCard;
    }
    return switch (state.stage) {
      MifareWriteStage.checkingCard =>
        isNdef ? l10n.ndefWriteChecking : l10n.cardWriteCheckingCard,
      MifareWriteStage.checkingPermissions => l10n.cardWriteCheckingPermissions,
      MifareWriteStage.writingData =>
        isNdef ? l10n.ndefWriteData : l10n.cardWriteWritingData,
      MifareWriteStage.lockingCard => l10n.cardWriteLockingCard,
      MifareWriteStage.verifying =>
        isNdef ? l10n.ndefWriteVerifying : l10n.cardWriteVerifying,
      null => l10n.cardWriteWaitingForCard,
    };
  }

  String _failureText(MifareWriteFailure? failure) => switch (failure) {
    MifareWriteFailure.capacityExceeded => l10n.ndefCapacityExceeded,
    MifareWriteFailure.unsupportedCard =>
      isNdef ? l10n.ndefUnsupportedTarget : l10n.cardWriteUnsupportedTarget,
    MifareWriteFailure.authenticationFailed => l10n.cardWriteUnknownKey,
    MifareWriteFailure.invalidAccessBits => l10n.cardWriteInvalidAccessBits,
    MifareWriteFailure.permissionDenied => l10n.cardWritePermissionDenied,
    MifareWriteFailure.cardRemoved => l10n.cardWriteCardRemoved,
    MifareWriteFailure.verificationFailed => l10n.cardWriteVerificationFailed,
    MifareWriteFailure.cancelled => l10n.cardWriteCancelled,
    MifareWriteFailure.writeFailed || null => l10n.cardWriteFailed,
  };
}
