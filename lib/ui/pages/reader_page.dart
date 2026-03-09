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

  void _onResendHistoryItem(WidgetRef ref, ScanLog log) {
    ref.read(cardSenderProvider.notifier).sendCard(log.card, triggerId: log.id);
  }

  Widget _buildNfcStatusPill(BuildContext context, WidgetRef ref) {
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
              Icons.nfc,
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

  Widget _buildNfcInfoDisplay(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final nfcState = ref.watch(nfcProvider);

    return Container(
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
        borderRadius: BorderRadius.circular(24),
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
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Animation/Pattern
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.contactless_outlined,
              size: 180,
              color: colorScheme.primary.withValues(alpha: 0.03),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulseNfcIcon(isScanning: nfcState.isScanning),
              const SizedBox(height: 20),
              Text(
                nfcState.isScanning ? 'Ready to Scan' : 'NFC Inactive',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  nfcState.isScanning
                      ? 'Hold your card near the NFC reader area of your device.'
                      : 'NFC service is currently unavailable or disabled.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (nfcState.isProcessing)
            Container(
              color: colorScheme.surface.withValues(alpha: 0.7),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildInstanceCard(BuildContext context, dynamic activeInstance) {
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
              ? _buildActiveInstanceRow(context, activeInstance)
              : _buildNoInstanceRow(context),
        ),
      ),
    );
  }

  Widget _buildActiveInstanceRow(BuildContext context, dynamic activeInstance) {
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

  Widget _buildNoInstanceRow(BuildContext context) {
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

  Widget _buildHistorySection(
    BuildContext context,
    WidgetRef ref,
    List<ScanLog> scanLogs,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Scans', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => context.push('/scan_logs'),
              child: const Text('View All Logs'),
            ),
          ],
        ),
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
            itemBuilder: (context, index) =>
                _buildHistoryItem(context, ref, scanLogs[index]),
          ),
      ],
    );
  }

  Widget _buildHistoryItem(BuildContext context, WidgetRef ref, ScanLog log) {
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
                  : () => _onResendHistoryItem(ref, log),
              tooltip: 'Resend to active instance',
              color: isAnyCardSending ? colorScheme.outline : null,
            ),
      onTap: () => context.push('/card_detail', extra: log.card),
    );
  }

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
              _buildNfcStatusPill(context, ref),
              const SizedBox(height: 16),
              _buildNfcInfoDisplay(context, ref),
              const SizedBox(height: 24),
              _buildInstanceCard(context, activeInstance),
              const SizedBox(height: 32),
              _buildHistorySection(context, ref, scanLogs),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
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
