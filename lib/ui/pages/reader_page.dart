import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../models/scan_log.dart';
import '../../providers/card_sender.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/nfc_provider.dart';
import '../../utils/icon_utils.dart';

class ReaderPage extends HookConsumerWidget {
  const ReaderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeInstance = ref.watch(activeInstanceProvider);
    final scanLogs = ref.watch(scanLogsProvider).reversed.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/logo.svg',
              height: 24,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurface,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
            const Text('HINATA Go'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.push('/camera'),
            tooltip: 'Scan QR Code',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _NfcStatusPill(),
              const SizedBox(height: 16),
              const _NfcInfoDisplay(),
              const SizedBox(height: 24),
              _InstanceCard(activeInstance: activeInstance),
              const SizedBox(height: 32),
              _HistorySection(scanLogs: scanLogs),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _NfcStatusPill extends ConsumerWidget {
  const _NfcStatusPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nfcState = ref.watch(nfcProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final Color bgColor = nfcState.isScanning
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final Color fgColor = nfcState.isScanning
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contactless_outlined,
              color: nfcState.isScanning
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                nfcState.status,
                key: ValueKey(nfcState.status),
                style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NfcInfoDisplay extends ConsumerWidget {
  const _NfcInfoDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final nfcState = ref.watch(nfcProvider);
    final isIOS = !kIsWeb && Platform.isIOS;
    final borderRadius = BorderRadius.circular(24);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 240,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surfaceContainerHighest,
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: borderRadius,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: isIOS
              ? () => ref.read(nfcProvider.notifier).startSession()
              : null,
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _NfcInfoBackgroundIcon(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PulseNfcIcon(isScanning: nfcState.isScanning),
                  const SizedBox(height: 20),
                  _NfcInfoText(isScanning: nfcState.isScanning, isIOS: isIOS),
                ],
              ),
              if (nfcState.isProcessing) const _NfcProcessingOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NfcInfoBackgroundIcon extends StatelessWidget {
  const _NfcInfoBackgroundIcon();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -20,
      bottom: -20,
      child: Icon(
        Icons.contactless_outlined,
        size: 180,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.03),
      ),
    );
  }
}

class _NfcInfoText extends StatelessWidget {
  final bool isScanning;
  final bool isIOS;

  const _NfcInfoText({required this.isScanning, required this.isIOS});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = isIOS
        ? (isScanning ? 'Scanning...' : 'Tap to Scan')
        : (isScanning ? 'Ready to Scan' : 'NFC Inactive');
    final subtitle = isIOS
        ? (isScanning
              ? 'Hold your card near the top of your iPhone.'
              : 'Tap this area to activate the NFC reader.')
        : (isScanning
              ? 'Hold your card near the NFC reader area of your device.'
              : 'NFC service is currently unavailable or disabled.');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _NfcProcessingOverlay extends StatelessWidget {
  const _NfcProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _InstanceCard extends StatelessWidget {
  final dynamic activeInstance;
  const _InstanceCard({required this.activeInstance});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/instances'),
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: activeInstance != null
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: activeInstance != null
              ? _ActiveInstanceRow(activeInstance: activeInstance)
              : const _NoInstanceRow(),
        ),
      ),
    );
  }
}

class _ActiveInstanceRow extends StatelessWidget {
  final dynamic activeInstance;
  const _ActiveInstanceRow({required this.activeInstance});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgColor = colorScheme.onPrimaryContainer;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: fgColor.withValues(alpha: 0.1),
          child: Text(
            IconUtils.getEmoji(activeInstance.icon),
            style: const TextStyle(fontSize: 24),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activeInstance.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activeInstance.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fgColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.arrow_drop_down, color: fgColor),
      ],
    );
  }
}

class _NoInstanceRow extends StatelessWidget {
  const _NoInstanceRow();

  @override
  Widget build(BuildContext context) {
    final fgColor = Theme.of(context).colorScheme.onErrorContainer;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: fgColor.withValues(alpha: 0.1),
          child: Icon(Icons.warning, color: fgColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'No active instance selected.\nTap to select.',
            style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
          ),
        ),
        Icon(Icons.arrow_drop_down, color: fgColor),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  final List<ScanLog> scanLogs;
  const _HistorySection({required this.scanLogs});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _HistoryHeader(),
        const Divider(),
        if (scanLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('No recent scans.')),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: scanLogs.length,
            itemBuilder: (context, index) => _HistoryItem(log: scanLogs[index]),
          ),
      ],
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Recent Scans', style: Theme.of(context).textTheme.titleLarge),
        TextButton(
          onPressed: () => context.push('/scan_logs'),
          child: const Text('View All Logs'),
        ),
      ],
    );
  }
}

class _HistoryItem extends ConsumerWidget {
  final ScanLog log;
  const _HistoryItem({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final senderState = ref.watch(cardSenderProvider);

    final isThisCardSending =
        senderState.isSending && senderState.triggerId == log.id;
    final isAnyCardSending = senderState.isSending;

    String displaySource = log.source;
    if (log.source == 'NFC') {
      if (log.apiType != 'nfc') {
        displaySource = 'NFC (${log.displayType})';
      }
    } else if (log.source == 'Direct') {
      displaySource = 'Saved Cards';
    }

    IconData sourceIcon = Icons.qr_code;
    if (log.source == 'NFC') sourceIcon = Icons.nfc;
    if (log.source == 'Direct') sourceIcon = Icons.credit_card;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(
          sourceIcon,
          color: colorScheme.onSecondaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        log.showValue,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '$displaySource • ${log.timestamp.toString().substring(5, 16)}',
      ),
      trailing: isThisCardSending
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.send, size: 20),
              onPressed: isAnyCardSending
                  ? null
                  : () {
                      ref
                          .read(cardSenderProvider.notifier)
                          .sendCard(log.card, triggerId: log.id);
                    },
              tooltip: 'Resend to active instance',
              color: isAnyCardSending ? colorScheme.outline : null,
            ),
      onTap: () => context.push('/card_detail', extra: log.card),
    );
  }
}

class _PulseNfcIcon extends HookWidget {
  final bool isScanning;
  const _PulseNfcIcon({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(seconds: 2),
    );

    useEffect(() {
      if (isScanning) {
        controller.repeat(reverse: true);
      } else {
        controller.stop();
      }
      return null;
    }, [isScanning]);

    final animation = useMemoized(
      () => Tween<double>(
        begin: 1.0,
        end: 1.1,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
      [controller],
    );

    if (!isScanning) {
      return Icon(
        Icons.nfc,
        size: 72,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      );
    }

    return ScaleTransition(
      scale: animation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.nfc,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
