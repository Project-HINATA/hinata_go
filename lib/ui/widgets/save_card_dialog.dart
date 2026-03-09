import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/card/card.dart';
import '../../models/card/saved_card.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/snackbar_utils.dart';

class SaveCardDialog extends ConsumerStatefulWidget {
  final ICCard card;
  final String? initialName;
  final String source;

  const SaveCardDialog({
    super.key,
    required this.card,
    this.initialName,
    required this.source,
  });

  @override
  ConsumerState<SaveCardDialog> createState() => _SaveCardDialogState();
}

class _SaveCardDialogState extends ConsumerState<SaveCardDialog> {
  late TextEditingController _nameController;
  late String _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialName ?? widget.card.name,
    );
    _selectedFolderId = 'favorites_folder';

    // Initial folder selection logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final folders = ref
          .read(cardFoldersProvider)
          .where((f) => f.id != 'history_folder')
          .toList();
      if (folders.isNotEmpty) {
        setState(() {
          if (folders.any((f) => f.id == 'favorites_folder')) {
            _selectedFolderId = 'favorites_folder';
          } else {
            _selectedFolderId = folders.first.id;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    return AlertDialog(
      title: const Text('Save to Folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name / Description'),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedFolderId,
            decoration: const InputDecoration(labelText: 'Folder'),
            items: folders.map((folder) {
              return DropdownMenuItem(
                value: folder.id,
                child: Text(folder.name),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedFolderId = val;
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
            if (_nameController.text.isNotEmpty) {
              final newCard = SavedCard(
                id: const Uuid().v4(),
                name: _nameController.text,
                card: widget.card,
                folderId: _selectedFolderId,
                source: widget.source,
              );
              ref.read(savedCardsProvider.notifier).addCard(newCard);
              ScaffoldMessenger.of(context).showQuickSnackBar(
                SnackBar(
                  content: Text(
                    'Saved "${_nameController.text}" to ${folders.firstWhere((f) => f.id == _selectedFolderId).name}.',
                  ),
                ),
              );
              Navigator.pop(context, true);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
