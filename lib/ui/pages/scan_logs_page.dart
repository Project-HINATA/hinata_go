import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/bag_card.dart';
import '../../models/scan_log.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/snackbar_utils.dart';

class ScanLogsPage extends ConsumerStatefulWidget {
  const ScanLogsPage({super.key});

  @override
  ConsumerState<ScanLogsPage> createState() => _ScanLogsPageState();
}

class _ScanLogsPageState extends ConsumerState<ScanLogsPage> {
  void _showSaveToBagDialog(ScanLog log) {
    final nameController = TextEditingController();
    String selectedFolderId = 'favorites_folder'; // Default to favorites

    // Make sure we have the latest folders
    final folders = ref
        .read(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();
    if (folders.isNotEmpty && folders.any((f) => f.id == 'favorites_folder')) {
      selectedFolderId = 'favorites_folder';
    } else if (folders.isNotEmpty) {
      selectedFolderId = folders.first.id;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Save to Saved Cards'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name / Description',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedFolderId,
                    decoration: const InputDecoration(labelText: 'Folder'),
                    items: [
                      ...folders.map((folder) {
                        return DropdownMenuItem(
                          value: folder.id,
                          child: Text(folder.name),
                        );
                      }),
                      // Quick creation from logs isn't perfectly clean without a nested dialog,
                      // but we can prompt them. For simplicity in context we stick to existing folders
                      // or we trigger a nested dialog.
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedFolderId = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final newCard = BagCard(
                        id: const Uuid().v4(),
                        name: nameController.text,
                        value: log.value,
                        showValue: log.showValue,
                        folderId: selectedFolderId,
                        source: log.source,
                        apiType: log.apiType,
                        displayType: log.displayType,
                      );
                      ref.read(bagCardsProvider.notifier).addCard(newCard);
                      ScaffoldMessenger.of(context).showQuickSnackBar(
                        SnackBar(
                          content: Text(
                            'Saved "${nameController.text}" to saved cards.',
                          ),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
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
              itemBuilder: (context, index) {
                final log = reversedLogs[index];
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
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                );
              },
            ),
    );
  }
}
