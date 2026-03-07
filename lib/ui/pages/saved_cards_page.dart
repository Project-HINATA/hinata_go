import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/bag_card.dart';
import '../../models/card_folder.dart';
import '../../models/scan_log.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_service.dart';

class SavedCardsPage extends ConsumerStatefulWidget {
  const SavedCardsPage({super.key});

  @override
  ConsumerState<SavedCardsPage> createState() => _SavedCardsPageState();
}

class _SavedCardsPageState extends ConsumerState<SavedCardsPage> {
  bool _isProcessing = false;
  String _selectedFolderId = 'history_folder'; // Default folder

  void _showAddCardDialog() {
    if (_selectedFolderId == 'history_folder') return;

    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final folders = ref
        .read(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Card Manually'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name / Description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedFolderId,
                    decoration: const InputDecoration(labelText: 'Folder'),
                    items: [
                      ...folders.map((folder) {
                        return DropdownMenuItem(
                          value: folder.id,
                          child: Text(folder.name),
                        );
                      }),
                      const DropdownMenuItem(
                        value: 'CREATE_NEW',
                        child: Text(
                          '+ New Folder',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                    onChanged: (val) => _onFolderDropdownChanged(val, setState),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valueController,
                    decoration: const InputDecoration(
                      labelText: 'Card Value / UID',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => _onSaveCard(
                    nameController.text.trim(),
                    valueController.text.trim(),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddFolderDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Folder Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _onCreateFolder(nameController.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _onFolderDropdownChanged(String? val, StateSetter setDialogState) {
    if (val == 'CREATE_NEW') {
      Navigator.pop(context);
      _showAddFolderDialog();
    } else if (val != null) {
      setDialogState(() {
        _selectedFolderId = val;
      });
    }
  }

  void _onSaveCard(String name, String value) {
    if (name.isNotEmpty && value.isNotEmpty) {
      final newCard = BagCard(
        id: const Uuid().v4(),
        name: name,
        value: value,
        showValue: value,
        folderId: _selectedFolderId,
        source: 'Direct',
        apiType: 'Direct',
        displayType: 'Manual Entry',
      );
      ref.read(bagCardsProvider.notifier).addCard(newCard);
      Navigator.pop(context);
    }
  }

  void _onCreateFolder(String name) {
    if (name.isNotEmpty) {
      final newFolder = CardFolder(id: const Uuid().v4(), name: name);
      ref.read(cardFoldersProvider.notifier).addFolder(newFolder);
      setState(() {
        _selectedFolderId = newFolder.id;
      });
      Navigator.pop(context);
    }
  }

  void _performDeleteFolder(String folderId) {
    ref.read(cardFoldersProvider.notifier).removeFolder(folderId);
    setState(() {
      _selectedFolderId = 'history_folder';
    });
    Navigator.pop(context);
  }

  void _onDeleteFolder(CardFolder folder) {
    if (folder.id == 'history_folder' || folder.id == 'favorites_folder') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete default folders.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: Text(
          'Are you sure you want to delete "${folder.name}" and all cards inside it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _performDeleteFolder(folder.id),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onSelectFolder(bool selected, String folderId) {
    if (selected) {
      setState(() {
        _selectedFolderId = folderId;
      });
    }
  }

  Future<void> _sendCardData(BagCard card) async {
    if (_isProcessing) return;

    // Create ScanLog for Direct send
    final newLog = ScanLog(
      id: const Uuid().v4(),
      value: card.value,
      showValue: card.showValue,
      source: 'Direct',
      apiType: card.apiType,
      displayType: card.displayType,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    final enableSecondaryConfirmation = ref
        .read(settingsProvider)
        .enableSecondaryConfirmation;
    if (enableSecondaryConfirmation) {
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Confirm Send'),
            content: Text(
              'Are you sure you want to send this card?\nValue: ${card.showValue}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (shouldSend != true) return;
    }

    setState(() {
      _isProcessing = true;
    });

    final activeInstance = ref.read(activeInstanceProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (activeInstance == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No active instance set. Please select one in Instances tab.',
          ),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Sending ${card.name} to ${activeInstance.name}...'),
        ),
      );

      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.sendCardData(
        instance: activeInstance,
        type: card.apiType,
        value: card.value,
      );

      if (!mounted) return;

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Success: Data sent.')),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed: Could not send data.')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
      });
      // Delay slightly to show processing state and prevent spam
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Builder methods
  // ---------------------------------------------------------------------------

  Widget _buildDismissBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Widget _buildCardItem(BagCard card) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(card.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) {
        ref.read(bagCardsProvider.notifier).removeCard(card.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.credit_card, color: colorScheme.primary),
        ),
        title: Text(
          card.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Value: ${card.showValue}'),
        trailing: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => _sendCardData(card),
                tooltip: 'Send to active instance',
              ),
        onTap: () => _sendCardData(card),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(cardFoldersProvider);
    final allCards = ref.watch(bagCardsProvider);
    final folderCards = allCards
        .where((c) => c.folderId == _selectedFolderId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: _showAddFolderDialog,
            tooltip: 'New Folder',
          ),
        ],
      ),
      body: Column(
        children: [
          // Folder Selection Strip
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                final isSelected = folder.id == _selectedFolderId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onLongPress: () => _onDeleteFolder(folder),
                    child: FilterChip(
                      label: Text(folder.name),
                      selected: isSelected,
                      onSelected: (selected) =>
                          _onSelectFolder(selected, folder.id),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Cards List
          Expanded(
            child: folderCards.isEmpty
                ? const Center(child: Text('No cards in this folder.'))
                : ListView.builder(
                    itemCount: folderCards.length,
                    itemBuilder: (context, index) =>
                        _buildCardItem(folderCards[index]),
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedFolderId == 'history_folder'
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddCardDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Card'),
            ),
    );
  }
}
