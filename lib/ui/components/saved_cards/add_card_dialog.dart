import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import '../../../models/card/aime.dart';
import '../../../models/card/saved_card.dart';
import '../../../providers/app_state_provider.dart';
import '../../../utils/hex_utils.dart';
import '../../../l10n/l10n.dart';
import '../../ui_text.dart';

class AddCardDialog extends HookConsumerWidget {
  final String initialFolderId;
  final VoidCallback onAddFolderRequested;

  const AddCardDialog({
    super.key,
    required this.initialFolderId,
    required this.onAddFolderRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();
    final valueController = useTextEditingController();
    final selectedFolderIdState = useState(initialFolderId);

    final name = useListenableSelector(
      nameController,
      () => nameController.text.trim(),
    );
    final value = useListenableSelector(
      valueController,
      () => valueController.text.trim(),
    );

    final isFormValid =
        name.isNotEmpty && value.length == 20 && !value.startsWith('3');

    void onSave() {
      if (!isFormValid) return;

      final accessCodeBytes = HexUtils.hexToBytes(value);
      final aime = Aime(Uint8List(4), 0x08, 0x0004, accessCodeBytes);
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

    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();

    return AlertDialog(
      title: Text(context.l10n.addCardManually),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: context.l10n.nameDescription,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedFolderIdState.value),
              initialValue: selectedFolderIdState.value,
              decoration: InputDecoration(labelText: context.l10n.folder),
              items: [
                ...folders.map(
                  (folder) => DropdownMenuItem(
                    value: folder.id,
                    child: Text(
                      folderDisplayName(context, folder.id, folder.name),
                    ),
                  ),
                ),
                DropdownMenuItem(
                  value: 'CREATE_NEW',
                  child: Text(
                    context.l10n.newFolderOption,
                    style: const TextStyle(color: Colors.blue),
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
              decoration: InputDecoration(
                labelText: context.l10n.accessCode,
                helperText:
                    value.isNotEmpty &&
                        (value.length != 20 || value.startsWith('3'))
                    ? context.l10n.invalidAccessCodeLength
                    : null,
                helperMaxLines: 3,
                helperStyle: const TextStyle(color: Colors.orange),
              ),
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
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: isFormValid ? onSave : null,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
