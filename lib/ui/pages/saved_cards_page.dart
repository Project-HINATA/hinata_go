import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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

class SavedCardsPage extends HookConsumerWidget {
  const SavedCardsPage({super.key});

  void _showAddCardDialog(
    BuildContext context,
    String selectedFolderId,
    ValueSetter<String> onFolderCreated,
  ) {
    if (selectedFolderId == 'history_folder') return;
    showDialog(
      context: context,
      builder: (context) => _AddCardDialog(
        initialFolderId: selectedFolderId,
        onAddFolderRequested: () =>
            _showAddFolderDialog(context, onFolderCreated),
      ),
    );
  }

  void _showAddFolderDialog(
    BuildContext context,
    ValueSetter<String> onFolderCreated,
  ) {
    showDialog(
      context: context,
      builder: (context) => _AddFolderDialog(onFolderCreated: onFolderCreated),
    );
  }

  void _performDeleteFolder(
    BuildContext dialogContext,
    WidgetRef ref,
    String folderId,
    ValueSetter<String> setSelectedFolderId,
  ) {
    ref.read(cardFoldersProvider.notifier).removeFolder(folderId);
    setSelectedFolderId('favorites_folder');
    Navigator.pop(dialogContext);
  }

  void _onDeleteFolder(
    BuildContext context,
    WidgetRef ref,
    CardFolder folder,
    ValueSetter<String> setSelectedFolderId,
  ) {
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
            onPressed: () => _performDeleteFolder(
              dialogContext,
              ref,
              folder.id,
              setSelectedFolderId,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCardData(
    BuildContext context,
    WidgetRef ref,
    SavedCard card,
  ) async {
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

  Widget _buildCardItem(BuildContext context, WidgetRef ref, SavedCard card) {
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
                onPressed: isAnyCardSending
                    ? null
                    : () => _sendCardData(context, ref, card),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFolderIdState = useState('favorites_folder');
    final folders = ref.watch(cardFoldersProvider);
    final allCards = ref.watch(savedCardsProvider);
    final folderCards = allCards
        .where((c) => c.folderId == selectedFolderIdState.value)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: () => _showAddFolderDialog(
              context,
              (newId) => selectedFolderIdState.value = newId,
            ),
            tooltip: 'New Folder',
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) =>
            _handleSwipe(context, details, folders, selectedFolderIdState),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            _buildFolderSelectionStrip(ref, folders, selectedFolderIdState),
            const Divider(height: 1),
            _buildCardsList(ref, folderCards),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(context, selectedFolderIdState),
    );
  }

  void _handleSwipe(
    BuildContext context,
    DragEndDetails details,
    List<CardFolder> folders,
    ValueNotifier<String> selectedFolderIdState,
  ) {
    final double velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 300) return;

    final currentFolderIndex = folders.indexWhere(
      (f) => f.id == selectedFolderIdState.value,
    );
    if (currentFolderIndex == -1) return;

    if (velocity > 0) {
      // Swiped right -> go to previous folder
      if (currentFolderIndex > 0) {
        selectedFolderIdState.value = folders[currentFolderIndex - 1].id;
      } else {
        // Already at first folder, go to previous tab
        context.go('/reader');
      }
    } else {
      // Swiped left -> go to next folder
      if (currentFolderIndex < folders.length - 1) {
        selectedFolderIdState.value = folders[currentFolderIndex + 1].id;
      } else {
        // Already at last folder, go to next tab
        context.go('/settings');
      }
    }
  }

  Widget _buildFolderSelectionStrip(
    WidgetRef ref,
    List<CardFolder> folders,
    ValueNotifier<String> selectedFolderIdState,
  ) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = folder.id == selectedFolderIdState.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onLongPress: () => _onDeleteFolder(
                context,
                ref,
                folder,
                (newId) => selectedFolderIdState.value = newId,
              ),
              child: FilterChip(
                label: Text(folder.name),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    selectedFolderIdState.value = folder.id;
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardsList(WidgetRef ref, List<SavedCard> folderCards) {
    return Expanded(
      child: folderCards.isEmpty
          ? const Center(child: Text('No cards in this folder.'))
          : ListView.builder(
              itemCount: folderCards.length,
              itemBuilder: (context, index) =>
                  _buildCardItem(context, ref, folderCards[index]),
            ),
    );
  }

  Widget? _buildFAB(
    BuildContext context,
    ValueNotifier<String> selectedFolderIdState,
  ) {
    if (selectedFolderIdState.value == 'history_folder') return null;
    return FloatingActionButton.extended(
      onPressed: () => _showAddCardDialog(
        context,
        selectedFolderIdState.value,
        (newId) => selectedFolderIdState.value = newId,
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add Card'),
    );
  }
}

class _AddCardDialog extends HookConsumerWidget {
  final String initialFolderId;
  final VoidCallback onAddFolderRequested;

  const _AddCardDialog({
    required this.initialFolderId,
    required this.onAddFolderRequested,
  });

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
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();
    final valueController = useTextEditingController();
    final selectedFolderIdState = useState(initialFolderId);

    void onSave() {
      final name = nameController.text.trim();
      final value = valueController.text.trim();
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
          folderId: selectedFolderIdState.value,
          source: 'Direct',
        );
        ref.read(savedCardsProvider.notifier).addCard(newCard);
        Navigator.pop(context);
      }
    }

    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    return AlertDialog(
      title: const Text('Add Card Manually'),
      content: SingleChildScrollView(
        child: Column(
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
              key: ValueKey(selectedFolderIdState.value),
              initialValue: selectedFolderIdState.value,
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
                  onAddFolderRequested();
                } else if (val != null) {
                  selectedFolderIdState.value = val;
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Access Code'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(20),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}

class _AddFolderDialog extends HookConsumerWidget {
  final ValueChanged<String> onFolderCreated;
  const _AddFolderDialog({required this.onFolderCreated});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();

    void onCreate() {
      final name = nameController.text.trim();
      if (name.isNotEmpty) {
        final newFolder = CardFolder(id: const Uuid().v4(), name: name);
        ref.read(cardFoldersProvider.notifier).addFolder(newFolder);
        onFolderCreated(newFolder.id);
        Navigator.pop(context);
      }
    }

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
        FilledButton(onPressed: onCreate, child: const Text('Create')),
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
