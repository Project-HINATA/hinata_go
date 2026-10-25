import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/validators/felica_input_validator.dart';
import '../../../l10n/l10n.dart';
import '../../../models/card/card_tag.dart';
import '../../../models/card/felica.dart';
import 'add_card_dialog.dart';

/// Files a FeliCa card from its IDm, PMm and system codes.
class AddFelicaDialog extends HookConsumerWidget {
  final String initialFolderId;
  final VoidCallback onAddFolderRequested;

  const AddFelicaDialog({
    super.key,
    required this.initialFolderId,
    required this.onAddFolderRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();
    final idmController = useTextEditingController();
    final pmmController = useTextEditingController();
    final systemCodesController = useTextEditingController();
    final selectedFolderIdState = useState(
      initialFolderId == 'history_folder' ? '' : initialFolderId,
    );
    CardFolderField.seed(ref, selectedFolderIdState);

    String watch(TextEditingController controller) =>
        useListenableSelector(controller, () => controller.text.trim());
    final name = watch(nameController);
    final idmText = watch(idmController);
    final pmmText = watch(pmmController);
    final systemCodesText = watch(systemCodesController);

    final idm = FelicaInputValidator.parseBytes8(idmText);
    final pmm = FelicaInputValidator.parseBytes8(pmmText);
    final systemCodes = FelicaInputValidator.parseSystemCodes(systemCodesText);
    final isFormValid =
        name.isNotEmpty && idm != null && pmm != null && systemCodes != null;

    Future<void> onSave() async {
      if (!isFormValid) return;
      await saveDirectCard(
        context,
        ref,
        card: Felica(idm, pmm, systemCodes, tags: const [CardTag.felica]),
        name: name,
        folderId: selectedFolderIdState.value,
      );
    }

    return AlertDialog(
      title: Text(l10n.addFelicaCard),
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
            _HexField(
              controller: idmController,
              label: l10n.idm,
              hint: l10n.felicaBytesHint,
              error: idmText.isNotEmpty && idm == null
                  ? l10n.felicaInvalidBytes
                  : null,
            ),
            const SizedBox(height: 10),
            _HexField(
              controller: pmmController,
              label: l10n.pmm,
              hint: l10n.felicaBytesHint,
              error: pmmText.isNotEmpty && pmm == null
                  ? l10n.felicaInvalidBytes
                  : null,
            ),
            const SizedBox(height: 10),
            _HexField(
              controller: systemCodesController,
              label: l10n.systemCode,
              hint: l10n.felicaSystemCodesHint,
              error: systemCodesText.isNotEmpty && systemCodes == null
                  ? l10n.felicaInvalidSystemCodes(
                      FelicaInputValidator.maxSystemCodes,
                    )
                  : null,
              allowCommas: true,
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

class _HexField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? error;
  final bool allowCommas;

  const _HexField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.error,
    this.allowCommas = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: error ?? hint,
        helperMaxLines: 3,
        helperStyle: error == null
            ? null
            : const TextStyle(color: Colors.orange),
      ),
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(fontFamily: 'monospace'),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(allowCommas ? r'[0-9a-fA-F,，\s]' : r'[0-9a-fA-F\s:\-]'),
        ),
      ],
    );
  }
}
