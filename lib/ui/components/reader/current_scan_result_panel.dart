import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../models/card/card.dart';
import '../../../models/card/ndef.dart';
import '../../../models/card/scanned_card.dart';
import '../../../models/card/transit.dart';
import '../../../models/remote_instance.dart';
import '../../../providers/card_sender.dart';
import '../../../providers/current_scan_session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../components/instances/select_instance_dialog.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/save_card_dialog.dart';
import 'scanned_card_detail_v2.dart';
import 'transit_history_card.dart';
import 'ndef_records_card.dart';

class CurrentScanResultPanel extends HookConsumerWidget {
  const CurrentScanResultPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentScanSessionProvider);
    final currentScan = session.scannedCard;

    final card = currentScan?.card;
    final opensPrism =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android) &&
        card is NdefCard &&
        card.prismUrl != null;
    if (currentScan == null || opensPrism) {
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
        scannedCard: currentScan,
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
    required this.scannedCard,
    required this.card,
    required this.source,
    required this.showDismissControls,
    required this.animationController,
    required this.onSave,
    required this.onSend,
    required this.onClear,
  });

  final ScannedCard scannedCard;
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
          isUsable: scannedCard.isUsable,
          showDismissControls: showDismissControls,
          animationController: animationController,
          onClear: onClear,
        ),
        if (card is NdefCard) ...[
          const SizedBox(height: 16),
          NdefRecordsCard(card: card as NdefCard),
        ],
        if (card is TransitCard) ...[
          const SizedBox(height: 16),
          TransitHistoryCard(card: card as TransitCard),
        ],
        if (scannedCard.isUsable) ...[
          const SizedBox(height: 24),
          _ScanActionRow(
            onSave: onSave,
            onSend: card.gamePayload != null ? onSend : null,
          ),
        ],
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
    required this.isUsable,
    required this.showDismissControls,
    required this.animationController,
    required this.onClear,
  });

  final ICCard card;
  final String source;
  final bool isUsable;
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
          isUsable: isUsable,
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
  const _ScanActionRow({required this.onSave, this.onSend});

  final VoidCallback onSave;
  final Future<void> Function()? onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ScanActionButton(
            icon: Icons.save_alt,
            label: l10n.saveUpper,
            onPressed: onSave,
            style: AdaptiveButtonStyle.glass,
          ),
        ),
        if (onSend != null) ...[
          const SizedBox(width: 16),
          Expanded(
            child: _ScanActionButton(
              icon: Icons.send_rounded,
              label: l10n.sendUpper,
              onPressed: () => onSend!(),
              style: AdaptiveButtonStyle.prominentGlass,
            ),
          ),
        ],
      ],
    );
  }
}

/// A scan action, drawn as a native Liquid Glass pill on iOS, like the
/// bottom actions of the card detail page, and as a Material button elsewhere.
class _ScanActionButton extends StatelessWidget {
  const _ScanActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.style,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final AdaptiveButtonStyle style;

  /// Same height as the card detail's bottom actions.
  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    if (useCupertinoChrome) {
      final scheme = context.colorScheme;
      final foreground = style == AdaptiveButtonStyle.prominentGlass
          ? scheme.onPrimary
          : scheme.primary;
      return SizedBox(
        height: _height,
        child: AdaptiveButton.child(
          onPressed: onPressed ?? () {},
          style: style,
          size: AdaptiveButtonSize.large,
          enabled: onPressed != null,
          useSmoothRectangleBorder: false,
          color: style == AdaptiveButtonStyle.prominentGlass
              ? scheme.primary
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final materialStyle = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: 20),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    return style == AdaptiveButtonStyle.prominentGlass
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: materialStyle,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: materialStyle,
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
