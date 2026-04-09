import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import '../../../models/card_folder.dart';
import '../../../providers/app_state_provider.dart';
import '../../../l10n/l10n.dart';

class AddFolderDialog extends HookConsumerWidget {
  final ValueChanged<String> onFolderCreated;

  const AddFolderDialog({super.key, required this.onFolderCreated});

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
      title: Text(context.l10n.newFolder),
      content: TextField(
        controller: nameController,
        decoration: InputDecoration(labelText: context.l10n.folderName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: onCreate, child: Text(context.l10n.create)),
      ],
    );
  }
}
