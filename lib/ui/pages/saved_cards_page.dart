import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../models/card/saved_card.dart';
import '../../models/card/aime.dart';
import '../../models/card_folder.dart';
import '../../models/scan_log.dart';
import '../../providers/card_sender.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/notification_service.dart';

class SavedCardsPage extends ConsumerStatefulWidget {
  const SavedCardsPage({super.key});

  @override
  ConsumerState<SavedCardsPage> createState() => _SavedCardsPageState();
}

class _SavedCardsPageState extends ConsumerState<SavedCardsPage> {
  String _selectedFolderId = 'favorites_folder'; // Default folder

  void _showAddCardDialog() {
    if (_selectedFolderId == 'history_folder') return;
    showDialog(
      context: context,
      builder: (context) => _AddCardDialog(
        initialFolderId: _selectedFolderId,
        onAddFolderRequested: _showAddFolderDialog,
      ),
    );
  }

  void _showAddFolderDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddFolderDialog(
        onFolderCreated: (newFolderId) {
          setState(() {
            _selectedFolderId = newFolderId;
          });
        },
      ),
    );
  }

  void _performDeleteFolder(BuildContext dialogContext, String folderId) {
    ref.read(cardFoldersProvider.notifier).removeFolder(folderId);
    setState(() {
      _selectedFolderId = 'favorites_folder';
    });
    Navigator.pop(dialogContext);
  }

  void _onDeleteFolder(CardFolder folder) {
    if (folder.id == 'history_folder' || folder.id == 'favorites_folder') {
      ref
          .read(notificationServiceProvider)
          .showError('Cannot delete default folders.');
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: Text(
          'Are you sure you want to delete "${folder.name}" and all cards inside it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _performDeleteFolder(dialogContext, folder.id),
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

  Future<void> _sendCardData(SavedCard card) async {
    // Create ScanLog for Direct send
    final newLog = ScanLog(
      id: const Uuid().v4(),
      source: 'Direct',
      showValue: card.showValue,
      card: card.card,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    final enableSecondaryConfirmation = ref
        .read(settingsProvider)
        .enableSecondaryConfirmation;
    if (enableSecondaryConfirmation) {
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => _ConfirmSendDialog(card: card),
      );
      if (!mounted) return;
      if (shouldSend != true) return;
    }

    // Call decentralized card sender provider with triggerId for UI feedback
    await ref
        .read(cardSenderProvider.notifier)
        .sendCard(card.card, triggerId: card.id);
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

  Widget _buildCardItem(SavedCard card) {
    final colorScheme = Theme.of(context).colorScheme;

    final senderState = ref.watch(cardSenderProvider);
    final isThisCardSending =
        senderState.isSending && senderState.triggerId == card.id;
    final isAnyCardSending = senderState.isSending;

    return Dismissible(
      key: ValueKey(card.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) {
        ref.read(savedCardsProvider.notifier).removeCard(card.id);
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
        subtitle: Text(card.showValue),
        trailing: isThisCardSending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.send_rounded),
                onPressed: isAnyCardSending ? null : () => _sendCardData(card),
                tooltip: 'Quick Send',
                color: isAnyCardSending ? colorScheme.outline : null,
              ),
        onTap: () => context.push('/card_detail', extra: card.card),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(cardFoldersProvider);
    final allCards = ref.watch(savedCardsProvider);
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
      body: GestureDetector(
        onHorizontalDragEnd: (details) => _handleSwipe(details, folders),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            _buildFolderSelectionStrip(folders),
            const Divider(height: 1),
            _buildCardsList(folderCards),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  void _handleSwipe(DragEndDetails details, List<CardFolder> folders) {
    final double velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 300) return;

    final currentFolderIndex = folders.indexWhere(
      (f) => f.id == _selectedFolderId,
    );
    if (currentFolderIndex == -1) return;

    if (velocity > 0) {
      // Swiped right -> go to previous folder
      if (currentFolderIndex > 0) {
        setState(() {
          _selectedFolderId = folders[currentFolderIndex - 1].id;
        });
      } else {
        // Already at first folder, go to previous tab
        context.go('/reader');
      }
    } else {
      // Swiped left -> go to next folder
      if (currentFolderIndex < folders.length - 1) {
        setState(() {
          _selectedFolderId = folders[currentFolderIndex + 1].id;
        });
      } else {
        // Already at last folder, go to next tab
        context.go('/settings');
      }
    }
  }

  Widget _buildFolderSelectionStrip(List<CardFolder> folders) {
    return SizedBox(
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
                onSelected: (selected) => _onSelectFolder(selected, folder.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardsList(List<SavedCard> folderCards) {
    return Expanded(
      child: folderCards.isEmpty
          ? const Center(child: Text('No cards in this folder.'))
          : ListView.builder(
              itemCount: folderCards.length,
              itemBuilder: (context, index) =>
                  _buildCardItem(folderCards[index]),
            ),
    );
  }

  Widget? _buildFAB() {
    if (_selectedFolderId == 'history_folder') return null;
    return FloatingActionButton.extended(
      onPressed: _showAddCardDialog,
      icon: const Icon(Icons.add),
      label: const Text('Add Card'),
    );
  }
}

class _AddCardDialog extends ConsumerStatefulWidget {
  final String initialFolderId;
  final VoidCallback onAddFolderRequested;

  const _AddCardDialog({
    required this.initialFolderId,
    required this.onAddFolderRequested,
  });

  @override
  ConsumerState<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends ConsumerState<_AddCardDialog> {
  late TextEditingController _nameController;
  late TextEditingController _valueController;
  late String _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _valueController = TextEditingController();
    _selectedFolderId = widget.initialFolderId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final value = _valueController.text.trim();
    if (name.isNotEmpty && value.isNotEmpty) {
      // Manual entry is treated as Aime type
      final accessCodeBytes = _hexToBytes(value);
      final aime = Aime(
        Uint8List(4), // placeholder id
        0x08, // placeholder sak
        0x0004, // placeholder atqa
        accessCodeBytes,
      );
      final newCard = SavedCard(
        id: const Uuid().v4(),
        name: name,
        card: aime,
        folderId: _selectedFolderId,
        source: 'Direct',
      );
      ref.read(savedCardsProvider.notifier).addCard(newCard);
      Navigator.pop(context);
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    // If input is pure digits, treat it as access code string
    if (cleanHex.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanHex)) {
      return Uint8List.fromList(cleanHex.codeUnits);
    }
    final length = cleanHex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    return AlertDialog(
      title: const Text('Add Card Manually'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name / Description'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedFolderId),
            initialValue: _selectedFolderId,
            decoration: const InputDecoration(labelText: 'Folder'),
            items: [
              ...folders.map(
                (folder) => DropdownMenuItem(
                  value: folder.id,
                  child: Text(folder.name),
                ),
              ),
              const DropdownMenuItem(
                value: 'CREATE_NEW',
                child: Text(
                  '+ New Folder',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
            onChanged: (val) {
              if (val == 'CREATE_NEW') {
                Navigator.pop(context);
                widget.onAddFolderRequested();
              } else if (val != null) {
                setState(() {
                  _selectedFolderId = val;
                });
              }
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _valueController,
            decoration: const InputDecoration(labelText: 'Access Code'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(20),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Save')),
      ],
    );
  }
}

class _AddFolderDialog extends ConsumerStatefulWidget {
  final ValueChanged<String> onFolderCreated;
  const _AddFolderDialog({required this.onFolderCreated});

  @override
  ConsumerState<_AddFolderDialog> createState() => _AddFolderDialogState();
}

class _AddFolderDialogState extends ConsumerState<_AddFolderDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onCreate() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      final newFolder = CardFolder(id: const Uuid().v4(), name: name);
      ref.read(cardFoldersProvider.notifier).addFolder(newFolder);
      widget.onFolderCreated(newFolder.id);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Folder Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _onCreate, child: const Text('Create')),
      ],
    );
  }
}

class _ConfirmSendDialog extends StatelessWidget {
  final SavedCard card;
  const _ConfirmSendDialog({required this.card});

  @override
  Widget build(BuildContext context) {
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
  }
}
