import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../models/card/card.dart';
import '../../../models/remote_instance.dart';
import '../../../providers/card_sender.dart';
import '../../../providers/current_scan_session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../components/instances/select_instance_dialog.dart';
import '../../widgets/save_card_dialog.dart';
import 'scanned_card_detail_v2.dart';

class CurrentScanResultPanel extends HookConsumerWidget {
  const CurrentScanResultPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentScanSessionProvider);
    final currentScan = session.scannedCard;

    if (currentScan == null) {
      return const SizedBox.shrink();
    }

    final durationSeconds = ref.watch(settingsProvider).cardExpirationSeconds;
    final animationController = useAnimationController(
      duration: Duration(seconds: durationSeconds),
    );

    useEffect(() {
      animationController
        ..stop()
        ..value = 0;
      return null;
    }, [session.lastAcceptedScanAt]);

    useEffect(
      () {
        if (!session.showDismissControls) {
          animationController
            ..stop()
            ..value = 0;
          return null;
        }

        var isDisposed = false;
        animationController
          ..stop()
          ..value = 0;

        animationController.forward().then((_) {
          if (!isDisposed && context.mounted) {
            final latestSession = ref.read(currentScanSessionProvider);
            if (latestSession.lastAcceptedScanAt ==
                    session.lastAcceptedScanAt &&
                latestSession.showDismissControls) {
              ref.read(currentScanSessionProvider.notifier).clear();
            }
          }
        });

        return () {
          isDisposed = true;
          animationController.stop();
        };
      },
      [
        session.cardRemovedAt,
        session.lastAcceptedScanAt,
        session.showDismissControls,
      ],
    );

    return TweenAnimationBuilder<double>(
      key: ValueKey(
        'NormalDetail-${session.dedupeKey}-${session.lastAcceptedScanAt?.millisecondsSinceEpoch}',
      ),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.2, 0.8, 0.2, 1.0),
      builder: (context, value, child) {
        return _PanelEntranceTransition(value: value, child: child!);
      },
      child: _CurrentScanResultContent(
        card: currentScan.card,
        source: currentScan.source,
        showDismissControls: session.showDismissControls,
        animationController: animationController,
        onSave: () {
          showDialog(
            context: context,
            builder: (context) => SaveCardDialog(
              card: currentScan.card,
              source: currentScan.source,
            ),
          );
        },
        onSend: () async {
          final selectedInstance = await showDialog<RemoteInstance>(
            context: context,
            builder: (context) => const SelectInstanceDialog(),
          );
          if (selectedInstance != null) {
            await ref
                .read(cardSenderProvider.notifier)
                .sendCard(currentScan.card, targetInstance: selectedInstance);
          }
        },
        onClear: session.showDismissControls
            ? () {
                animationController.stop();
                ref.read(currentScanSessionProvider.notifier).clear();
              }
            : null,
      ),
    );
  }
}

class _PanelEntranceTransition extends StatelessWidget {
  const _PanelEntranceTransition({required this.value, required this.child});

  final double value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: child,
      ),
    );
  }
}

class _CurrentScanResultContent extends StatelessWidget {
  const _CurrentScanResultContent({
    required this.card,
    required this.source,
    required this.showDismissControls,
    required this.animationController,
    required this.onSave,
    required this.onSend,
    required this.onClear,
  });

  final ICCard card;
  final String source;
  final bool showDismissControls;
  final AnimationController animationController;
  final VoidCallback onSave;
  final Future<void> Function() onSend;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ScanDetailStack(
          card: card,
          source: source,
          showDismissControls: showDismissControls,
          animationController: animationController,
          onClear: onClear,
        ),
        const SizedBox(height: 24),
        _ScanActionRow(onSave: onSave, onSend: onSend),
        const SizedBox(height: 16),
        _ClearScanButton(onPressed: onClear),
      ],
    );
  }
}

class _ScanDetailStack extends StatelessWidget {
  const _ScanDetailStack({
    required this.card,
    required this.source,
    required this.showDismissControls,
    required this.animationController,
    required this.onClear,
  });

  final ICCard card;
  final String source;
  final bool showDismissControls;
  final AnimationController animationController;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScannedCardDetailV2(
          card: card,
          source: source,
          showCloseButtonSpace: showDismissControls,
        ),
        if (showDismissControls)
          Positioned(
            top: 12,
            right: 12,
            child: _TimedDismissButton(
              animationController: animationController,
              onTap: onClear!,
            ),
          ),
      ],
    );
  }
}

class _TimedDismissButton extends StatelessWidget {
  const _TimedDismissButton({
    required this.animationController,
    required this.onTap,
  });

  final AnimationController animationController;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return CircularProgressIndicator(
                  value: 1.0 - animationController.value,
                  strokeWidth: 2,
                  color: context.colorScheme.primary.withValues(alpha: 0.3),
                  backgroundColor: Colors.transparent,
                );
              },
            ),
          ),
          Icon(
            Icons.close_rounded,
            size: 14,
            color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _ScanActionRow extends StatelessWidget {
  const _ScanActionRow({required this.onSave, required this.onSend});

  final VoidCallback onSave;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ScanActionButton.outlined(
            icon: Icons.save_alt,
            label: context.l10n.saveUpper,
            onPressed: onSave,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ScanActionButton.filled(
            icon: Icons.send_rounded,
            label: context.l10n.sendUpper,
            onPressed: () => onSend(),
          ),
        ),
      ],
    );
  }
}

class _ScanActionButton extends StatelessWidget {
  const _ScanActionButton.outlined({
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : filled = false;

  const _ScanActionButton.filled({
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : filled = true;

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: 20),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          );
  }
}

class _ClearScanButton extends StatelessWidget {
  const _ClearScanButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: const Text('Clear Scan'),
      style: TextButton.styleFrom(foregroundColor: context.colorScheme.outline),
    );
  }
}
