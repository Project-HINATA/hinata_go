import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../l10n/l10n.dart';
import '../../../models/remote_instance.dart';
import '../../../providers/app_state_provider.dart';
import '../../../utils/icon_utils.dart';
import '../../../utils/validators.dart';

class InstanceDialog extends HookConsumerWidget {
  final RemoteInstance? existingInstance;

  const InstanceDialog({super.key, this.existingInstance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(
      text: existingInstance?.name,
    );
    final urlController = useTextEditingController(text: existingInstance?.url);
    final passwordController = useTextEditingController(
      text: existingInstance?.password,
    );

    final selectedIconState = useState(existingInstance?.icon ?? '🐻');
    final selectedTypeState = useState(
      existingInstance?.type ?? InstanceType.hinataIo,
    );
    final selectedUnitState = useState(existingInstance?.unit ?? 0);

    final name = useListenableSelector(
      nameController,
      () => nameController.text.trim(),
    );
    final url = useListenableSelector(
      urlController,
      () => urlController.text.trim(),
    );

    final isValidUrl = Validators.isValidInstanceUrl(
      url,
      selectedTypeState.value,
    );
    final isFormValid = name.isNotEmpty && url.isNotEmpty && isValidUrl;

    void onSave() {
      if (!isFormValid) return;
      final password = passwordController.text.trim();

      final newInstance = RemoteInstance(
        id: existingInstance?.id ?? const Uuid().v4(),
        name: name,
        url: Validators.buildValidUrl(url, selectedTypeState.value),
        icon: selectedIconState.value.isEmpty ? '🐻' : selectedIconState.value,
        type: selectedTypeState.value,
        unit: selectedUnitState.value,
        password: password,
      );

      if (existingInstance != null) {
        ref.read(instancesProvider.notifier).updateInstance(newInstance);
      } else {
        ref.read(instancesProvider.notifier).addInstance(newInstance);
        if (ref.read(instancesProvider).length == 1) {
          ref
              .read(activeInstanceIdProvider.notifier)
              .setActiveId(newInstance.id);
        }
      }
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(
        existingInstance != null
            ? context.l10n.editInstance
            : context.l10n.addInstance,
      ),
      content: _InstanceDialogContent(
        nameField: _buildNameField(context, nameController),
        typeDropdown: _buildTypeDropdown(context, selectedTypeState),
        urlField: _buildUrlField(context, urlController, url, isValidUrl),
        passwordField: _buildPasswordField(context, passwordController),
        unitDropdown: _buildUnitDropdown(context, selectedUnitState),
        showSpiceFields:
            selectedTypeState.value == InstanceType.spiceApi ||
            selectedTypeState.value == InstanceType.spiceApiWebSocket,
        iconSelection: _buildIconSelection(context, selectedIconState),
      ),
      actions: _buildActions(context, isFormValid, onSave),
    );
  }

  Widget _buildNameField(
    BuildContext context,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: context.l10n.nameExample),
    );
  }

  Widget _buildTypeDropdown(
    BuildContext context,
    ValueNotifier<InstanceType> typeState,
  ) {
    return DropdownButtonFormField<InstanceType>(
      initialValue: typeState.value,
      decoration: InputDecoration(labelText: context.l10n.instanceType),
      items: [
        DropdownMenuItem(
          value: InstanceType.hinataIo,
          child: Text(context.l10n.instanceTypeHinataIo),
        ),
        DropdownMenuItem(
          value: InstanceType.spiceApi,
          child: Text(context.l10n.instanceTypeSpiceApi),
        ),
        DropdownMenuItem(
          value: InstanceType.spiceApiWebSocket,
          child: Text(context.l10n.instanceTypeSpiceApiWebSocket),
        ),
      ],
      onChanged: (value) {
        if (value != null) typeState.value = value;
      },
    );
  }

  Widget _buildUrlField(
    BuildContext context,
    TextEditingController controller,
    String currentUrl,
    bool isValid,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: context.l10n.endpointLabel,
        helperText: currentUrl.isNotEmpty && !isValid
            ? context.l10n.invalidEndpoint
            : null,
        helperStyle: const TextStyle(color: Colors.orange),
      ),
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildPasswordField(
    BuildContext context,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: context.l10n.spiceApiPassword),
      obscureText: true,
    );
  }

  Widget _buildUnitDropdown(
    BuildContext context,
    ValueNotifier<int> unitState,
  ) {
    return DropdownButtonFormField<int>(
      initialValue: unitState.value,
      decoration: InputDecoration(labelText: context.l10n.spiceApiUnit),
      items: const [
        DropdownMenuItem(value: 0, child: Text('0')),
        DropdownMenuItem(value: 1, child: Text('1')),
      ],
      onChanged: (value) {
        if (value != null) unitState.value = value;
      },
    );
  }

  Widget _buildIconSelection(
    BuildContext context,
    ValueNotifier<String> iconState,
  ) {
    return _InstanceIconSelection(
      title: context.l10n.selectIcon,
      selectedIcon: iconState.value,
      onIconSelected: (iconName) => iconState.value = iconName,
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    bool isValid,
    VoidCallback onSave,
  ) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: isValid ? onSave : null,
        child: Text(context.l10n.save),
      ),
    ];
  }
}

class _InstanceDialogContent extends StatelessWidget {
  const _InstanceDialogContent({
    required this.nameField,
    required this.typeDropdown,
    required this.urlField,
    required this.passwordField,
    required this.unitDropdown,
    required this.showSpiceFields,
    required this.iconSelection,
  });

  final Widget nameField;
  final Widget typeDropdown;
  final Widget urlField;
  final Widget passwordField;
  final Widget unitDropdown;
  final bool showSpiceFields;
  final Widget iconSelection;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          nameField,
          const _DialogFieldGap(),
          typeDropdown,
          const _DialogFieldGap(),
          urlField,
          if (showSpiceFields) ...[
            const _DialogFieldGap(),
            passwordField,
            const _DialogFieldGap(),
            unitDropdown,
          ],
          const _DialogFieldGap(),
          iconSelection,
        ],
      ),
    );
  }
}

class _DialogFieldGap extends StatelessWidget {
  const _DialogFieldGap();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 10);
  }
}

class _InstanceIconSelection extends StatelessWidget {
  const _InstanceIconSelection({
    required this.title,
    required this.selectedIcon,
    required this.onIconSelected,
  });

  final String title;
  final String selectedIcon;
  final ValueChanged<String> onIconSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: IconUtils.availableIcons.map((iconName) {
            return _InstanceIconChip(
              iconName: iconName,
              selected: iconName == selectedIcon,
              onSelected: () => onIconSelected(iconName),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _InstanceIconChip extends StatelessWidget {
  const _InstanceIconChip({
    required this.iconName,
    required this.selected,
    required this.onSelected,
  });

  final String iconName;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        IconUtils.getEmoji(iconName),
        style: const TextStyle(fontSize: 24),
      ),
      selected: selected,
      onSelected: (selected) {
        if (selected) onSelected();
      },
    );
  }
}
