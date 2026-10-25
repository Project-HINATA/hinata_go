import 'package:cardcipher/bana.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import '../../../models/card/aime.dart';
import '../../../models/card/banapass.dart';
import '../../../models/card/card.dart';
import '../../../models/card/saved_card.dart';
import '../../../models/card_folder.dart';
import '../../../providers/app_state_provider.dart';
import '../../../core/validators/access_code_validator.dart';
import '../../../l10n/l10n.dart';
import '../../ui_text.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/native_alert.dart';

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
    // A card cannot be filed into history, so a page showing that folder
    // still opens the dialog on a folder the user can pick.
    final selectedFolderIdState = useState(
      initialFolderId == 'history_folder' ? '' : initialFolderId,
    );

    final name = useListenableSelector(
      nameController,
      () => nameController.text.trim(),
    );
    final value = useListenableSelector(
      valueController,
      () => valueController.text.trim(),
    );

    final isBanapass = AccessCodeValidator.startsWithBanapassPrefix(value);
    final isCodeValid = isBanapass
        ? BanapassCipher.isAvailable() &&
              AccessCodeValidator.isValidBanapassAccessCode(value)
        : AccessCodeValidator.isValidAimeAccessCode(value);
    final isFormValid = name.isNotEmpty && isCodeValid;

    CardFolderField.seed(ref, selectedFolderIdState);

    Future<void> onSave() async {
      if (!isFormValid) return;

      final accessCodeBytes = ICCard.hexToBytes(value);
      final card = isBanapass
          ? Banapass.fromAccessCode(
              accessCode: value,
              dualKey: true,
              tags: const [CardTag.banapass],
            )
          : Aime(accessCodeBytes, tags: const [CardTag.aime]);
      await saveDirectCard(
        context,
        ref,
        card: card,
        name: name,
        folderId: selectedFolderIdState.value,
      );
    }

    return AlertDialog(
      title: Text(l10n.addAimeBanapass),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: l10n.nameDescription),
            ),
            const SizedBox(height: 10),
            CardFolderField(
              selected: selectedFolderIdState,
              onAddFolderRequested: onAddFolderRequested,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueController,
              decoration: InputDecoration(
                labelText: l10n.accessCode,
                helperText: value.isNotEmpty && !isCodeValid
                    ? (isBanapass
                          ? l10n.banapassAccessCodeCannotCreate
                          : l10n.invalidAccessCodeLength)
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
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: isFormValid ? onSave : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Files [card] as a hand-made card, asking before replacing a duplicate.
/// Closes the dialog once saved.
Future<void> saveDirectCard(
  BuildContext context,
  WidgetRef ref, {
  required ICCard card,
  required String name,
  required String folderId,
}) async {
  final notifier = ref.read(savedCardsProvider.notifier);
  final duplicate = notifier.findDuplicate(card, name, folderId);

  final newCard = SavedCard(
    id: const Uuid().v4(),
    name: name,
    card: card,
    folderId: folderId,
    source: 'Direct',
  );

  if (duplicate != null) {
    final confirm = useCupertinoChrome
        ? await showNativeConfirmation(
            context,
            title: l10n.duplicateCardTitle,
            message: l10n.duplicateCardPrompt,
            confirmLabel: l10n.overwrite,
            destructive: true,
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.duplicateCardTitle),
              content: Text(l10n.duplicateCardPrompt),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    l10n.overwrite,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          );

    if (confirm != true) return;

    notifier.replaceCard(duplicate, newCard);
  } else {
    notifier.addCard(newCard);
  }

  if (!context.mounted) return;
  Navigator.pop(context);
}

/// Picks the folder a hand-made card is filed into. History is left out:
/// it holds scans, not cards the user files.
class CardFolderField extends ConsumerWidget {
  final ValueNotifier<String> selected;
  final VoidCallback onAddFolderRequested;

  const CardFolderField({
    super.key,
    required this.selected,
    required this.onAddFolderRequested,
  });

  /// Called from the dialog's own build, before it can be saved from, so a
  /// card always lands in a folder the picker offers.
  static void seed(WidgetRef ref, ValueNotifier<String> selected) {
    final folders = _folders(ref);
    if (selected.value.isEmpty && folders.isNotEmpty) {
      selected.value = folders.first.id;
    }
  }

  static List<CardFolder> _folders(WidgetRef ref) => ref
      .watch(cardFoldersProvider)
      .where((f) => f.id != 'history_folder')
      .toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = _folders(ref);
    return NativeChoiceField<String>(
      label: l10n.folder,
      options: [
        for (final folder in folders)
          NativeChoice(
            label: folderDisplayName(folder.id, folder.name),
            value: folder.id,
          ),
        NativeChoice(label: l10n.newFolderOption, value: 'CREATE_NEW'),
      ],
      selected: selected.value,
      onChanged: (val) {
        if (val == 'CREATE_NEW') {
          Navigator.pop(context);
          onAddFolderRequested();
        } else {
          selected.value = val;
        }
      },
    );
  }
}
