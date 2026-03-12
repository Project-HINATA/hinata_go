import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';

import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/validators.dart';
import '../../utils/icon_utils.dart';
import '../../utils/snackbar_utils.dart';
import '../../l10n/l10n.dart';

class InstancesPage extends HookConsumerWidget {
  const InstancesPage({super.key});

  void _showInstanceDialog(
    BuildContext context, [
    RemoteInstance? existingInstance,
  ]) {
    showDialog(
      context: context,
      builder: (context) => _InstanceDialog(existingInstance: existingInstance),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final instances = ref.watch(instancesProvider);
    final activeId = ref.watch(activeInstanceIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.remoteInstances)),
      body: instances.isEmpty
          ? Center(child: Text(l10n.noInstancesConfigured))
          : ListView.builder(
              itemCount: instances.length,
              itemBuilder: (context, index) {
                final instance = instances[index];
                return _InstanceItem(
                  instance: instance,
                  isActive: instance.id == activeId,
                  onEdit: () => _showInstanceDialog(context, instance),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInstanceDialog(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.addInstance),
      ),
    );
  }
}

class _InstanceItem extends ConsumerWidget {
  final RemoteInstance instance;
  final bool isActive;
  final VoidCallback onEdit;

  const _InstanceItem({
    required this.instance,
    required this.isActive,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(instance.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        if (isActive) {
          ref.read(activeInstanceIdProvider.notifier).setActiveId(null);
        }
        ref.read(instancesProvider.notifier).removeInstance(instance.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          child: Text(
            IconUtils.getEmoji(instance.icon),
            style: const TextStyle(fontSize: 24),
          ),
        ),
        title: Text(
          instance.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          instance.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.check_circle, color: Colors.green),
              ),
            IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
          ],
        ),
        onTap: () {
          ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
          ScaffoldMessenger.of(context).showQuickSnackBar(
            SnackBar(
              content: Text(context.l10n.instanceNowActive(instance.name)),
            ),
          );
        },
      ),
    );
  }
}

class _InstanceDialog extends HookConsumerWidget {
  final RemoteInstance? existingInstance;
  const _InstanceDialog({this.existingInstance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(
      text: existingInstance?.name,
    );
    final urlController = useTextEditingController(text: existingInstance?.url);
    final selectedIconState = useState(existingInstance?.icon ?? '🐻');
    final selectedTypeState = useState(existingInstance?.type ?? InstanceType.hinataIo);

    void onSave() {
      final name = nameController.text.trim();
      final url = urlController.text.trim();

      if (name.isEmpty || url.isEmpty) return;

      final isValidUrl = Validators.isValidUrl(url);
      if (!isValidUrl) {
        ScaffoldMessenger.of(
          context,
        ).showQuickSnackBar(SnackBar(content: Text(context.l10n.invalidUrl)));
        return;
      }

      final newInstance = RemoteInstance(
        id: existingInstance?.id ?? const Uuid().v4(),
        name: name,
        url: url,
        icon: selectedIconState.value.isEmpty ? '🐻' : selectedIconState.value,
        type: selectedTypeState.value,
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

    final isEditing = existingInstance != null;

    return AlertDialog(
      title: Text(
        isEditing ? context.l10n.editInstance : context.l10n.addInstance,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: context.l10n.nameExample),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlController,
              decoration: InputDecoration(labelText: context.l10n.webhookUrl),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<InstanceType>(
              initialValue: selectedTypeState.value,
              decoration: InputDecoration(labelText: context.l10n.instanceType),
              items: [
                DropdownMenuItem(
                  value: InstanceType.hinataIo,
                  child: Text(context.l10n.instanceTypeHinataIo),
                ),
                DropdownMenuItem(
                  value: InstanceType.spiceApiUnit0,
                  child: Text(context.l10n.instanceTypeSpiceApiUnit0),
                ),
                DropdownMenuItem(
                  value: InstanceType.spiceApiUnit1,
                  child: Text(context.l10n.instanceTypeSpiceApiUnit1),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  selectedTypeState.value = value;
                }
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.selectIcon),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: IconUtils.availableIcons.map((iconName) {
                final isSelected = iconName == selectedIconState.value;
                return ChoiceChip(
                  label: Text(
                    IconUtils.getEmoji(iconName),
                    style: const TextStyle(fontSize: 24),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      selectedIconState.value = iconName;
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: onSave, child: Text(context.l10n.save)),
      ],
    );
  }
}
