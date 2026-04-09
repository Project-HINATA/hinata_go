import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/l10n.dart';
import '../../models/card/card.dart';
import '../../models/card/saved_card.dart';
import '../../models/card_folder.dart';
import '../../providers/app_state_provider.dart';
import '../../services/notification_service.dart';
import '../ui_text.dart';

class SaveCardDialog extends HookConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(
      text: initialName ?? card.name,
    );
    final selectedFolderIdState = useState('favorites_folder');

    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    useEffect(() {
      if (folders.isNotEmpty) {
        if (folders.any((f) => f.id == 'favorites_folder')) {
          selectedFolderIdState.value = 'favorites_folder';
        } else {
          selectedFolderIdState.value = folders.first.id;
        }
      }
      return null;
    }, []);

    return AlertDialog(
      title: Text(context.l10n.saveToFolder),
      content: _SaveCardDialogContent(
        nameField: _buildNameField(context, nameController),
        folderDropdown: _buildFolderDropdown(
          context,
          selectedFolderIdState,
          folders,
        ),
      ),
      actions: _buildActions(
        context,
        ref,
        nameController,
        selectedFolderIdState,
        folders,
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    TextEditingController nameController,
    ValueNotifier<String> selectedFolderIdState,
    List<CardFolder> folders,
  ) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => _saveCard(
          context,
          ref,
          nameController,
          selectedFolderIdState,
          folders,
        ),
        child: Text(context.l10n.save),
      ),
    ];
  }

  Widget _buildNameField(
    BuildContext context,
    TextEditingController nameController,
  ) {
    return TextField(
      controller: nameController,
      decoration: InputDecoration(labelText: context.l10n.nameDescription),
      autofocus: true,
    );
  }

  Widget _buildFolderDropdown(
    BuildContext context,
    ValueNotifier<String> selectedFolderIdState,
    List<CardFolder> folders,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: selectedFolderIdState.value,
      decoration: InputDecoration(labelText: context.l10n.folder),
      items: folders.map((folder) {
        return DropdownMenuItem(
          value: folder.id,
          child: Text(folderDisplayName(context, folder.id, folder.name)),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          selectedFolderIdState.value = val;
        }
      },
    );
  }

  void _saveCard(
    BuildContext context,
    WidgetRef ref,
    TextEditingController nameController,
    ValueNotifier<String> selectedFolderIdState,
    List<CardFolder> folders,
  ) {
    if (nameController.text.isEmpty) return;

    final newCard = SavedCard(
      id: const Uuid().v4(),
      name: nameController.text,
      card: card,
      folderId: selectedFolderIdState.value,
      source: source,
    );

    ref.read(savedCardsProvider.notifier).addCard(newCard);
    _showSaveSuccessSnackBar(
      context,
      ref,
      nameController.text,
      selectedFolderIdState.value,
      folders,
    );
    Navigator.pop(context, true);
  }

  void _showSaveSuccessSnackBar(
    BuildContext context,
    WidgetRef ref,
    String cardName,
    String folderId,
    List<CardFolder> folders,
  ) {
    try {
      final folder = folders.firstWhere((f) => f.id == folderId);
      ref
          .read(notificationServiceProvider)
          .showSuccess(
            context.l10n.savedToFolder(
              cardName,
              folderDisplayName(context, folderId, folder.name),
            ),
          );
    } catch (_) {
      // Fallback if folder not found
    }
  }
}

class _SaveCardDialogContent extends StatelessWidget {
  const _SaveCardDialogContent({
    required this.nameField,
    required this.folderDropdown,
  });

  final Widget nameField;
  final Widget folderDropdown;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [nameField, const SizedBox(height: 10), folderDropdown],
    );
  }
}
