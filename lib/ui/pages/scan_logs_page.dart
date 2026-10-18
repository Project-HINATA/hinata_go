import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../models/scan_log.dart';
import '../../providers/app_state_provider.dart';
import '../ui_text.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/save_card_dialog.dart';

class ScanLogsPage extends HookConsumerWidget {
  const ScanLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(scanLogsProvider);
    final reversedLogs = logs.reversed.toList();

    void clearLogs() => ref.read(scanLogsProvider.notifier).clearLogs();

    return AppScaffold(
      title: l10n.scanHistoryLogs,
      actions: [
        AdaptiveAppBarAction(
          iosSymbol: 'trash',
          icon: Icons.delete_sweep,
          label: l10n.clearHistory,
          onPressed: clearLogs,
        ),
      ],
      body: SafeArea(
        top: false,
        bottom: false,
        child: _ScanLogsBody(child: _buildBody(context, reversedLogs)),
      ),
      materialFloatingActionButton: reversedLogs.isEmpty
          ? null
          : FloatingActionButton.small(
              onPressed: clearLogs,
              tooltip: l10n.clearHistory,
              child: const Icon(Icons.delete_sweep),
            ),
    );
  }

  Widget _buildBody(BuildContext context, List<ScanLog> logs) {
    if (logs.isEmpty) {
      return Center(child: Text(l10n.noScanHistoryYet));
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) => _buildLogItem(
        context,
        logs[index],
        (log) => _showSaveToBagDialog(context, log),
      ),
    );
  }

  void _showSaveToBagDialog(BuildContext context, ScanLog log) {
    showDialog(
      context: context,
      builder: (context) => SaveCardDialog(card: log.card, source: log.source),
    );
  }

  Widget _buildLogItem(
    BuildContext context,
    ScanLog log,
    void Function(ScanLog) onSave,
  ) {
    final displaySource = scanSourceDisplayName(log);

    IconData sourceIcon = Icons.qr_code;
    if (log.source == 'NFC') sourceIcon = Icons.nfc;
    if (log.source == 'Direct') sourceIcon = Icons.credit_card;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.surfaceContainerHighest,
        child: log.card.logoPath != null
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: SvgPicture.asset(
                  log.card.logoPath!,
                  colorFilter: ColorFilter.mode(
                    context.colorScheme.primary,
                    BlendMode.srcIn,
                  ),
                ),
              )
            : Icon(sourceIcon, color: context.colorScheme.onSurfaceVariant),
      ),
      title: Text(
        log.showValue,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${context.l10n.sourceLine(displaySource)}\n${context.l10n.timeLine(log.timestamp.toString().substring(0, 19))}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.folder_special),
        tooltip: context.l10n.saveToSavedCards,
        onPressed: () => onSave(log),
      ),
      onTap: () => context.push('/card_detail', extra: log.card),
    );
  }
}

class _ScanLogsBody extends StatelessWidget {
  const _ScanLogsBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: child,
      ),
    );
  }
}
