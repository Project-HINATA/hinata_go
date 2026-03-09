import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/scan_log.dart';
import '../../providers/app_state_provider.dart';
import '../widgets/save_card_dialog.dart';

class ScanLogsPage extends ConsumerStatefulWidget {
  const ScanLogsPage({super.key});

  @override
  ConsumerState<ScanLogsPage> createState() => _ScanLogsPageState();
}

class _ScanLogsPageState extends ConsumerState<ScanLogsPage> {
  void _showSaveToBagDialog(ScanLog log) {
    showDialog(
      context: context,
      builder: (context) => SaveCardDialog(card: log.card, source: log.source),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(scanLogsProvider);
    final reversedLogs = logs.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear History',
            onPressed: () {
              ref.read(scanLogsProvider.notifier).clearLogs();
            },
          ),
        ],
      ),
      body: reversedLogs.isEmpty
          ? const Center(child: Text('No scan history yet.'))
          : ListView.builder(
              itemCount: reversedLogs.length,
              itemBuilder: (context, index) =>
                  _buildLogItem(reversedLogs[index]),
            ),
    );
  }

  Widget _buildLogItem(ScanLog log) {
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
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          sourceIcon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        log.showValue,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        'Source: $displaySource\nTime: ${log.timestamp.toString().substring(0, 19)}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.save_alt),
        tooltip: 'Save to Saved Cards',
        onPressed: () => _showSaveToBagDialog(log),
      ),
      onTap: () => context.push('/card_detail', extra: log.card),
    );
  }
}
