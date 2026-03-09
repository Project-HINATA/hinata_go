import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';

import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/validators.dart';
import '../../utils/icon_utils.dart';
import '../../utils/snackbar_utils.dart';

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

  void _onDismissInstance(
    WidgetRef ref,
    RemoteInstance instance,
    bool isActive,
  ) {
    if (isActive) {
      ref.read(activeInstanceIdProvider.notifier).setActiveId(null);
    }
    ref.read(instancesProvider.notifier).removeInstance(instance.id);
  }

  void _onTapInstance(
    BuildContext context,
    WidgetRef ref,
    RemoteInstance instance,
  ) {
    ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(content: Text('${instance.name} is now active')),
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Widget _buildInstanceItem(
    BuildContext context,
    WidgetRef ref,
    RemoteInstance instance,
    bool isActive,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(instance.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) => _onDismissInstance(ref, instance, isActive),
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
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showInstanceDialog(context, instance),
            ),
          ],
        ),
        onTap: () => _onTapInstance(context, ref, instance),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider);
    final activeId = ref.watch(activeInstanceIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Remote Instances')),
      body: instances.isEmpty
          ? const Center(child: Text('No instances configured.'))
          : ListView.builder(
              itemCount: instances.length,
              itemBuilder: (context, index) {
                final instance = instances[index];
                return _buildInstanceItem(
                  context,
                  ref,
                  instance,
                  instance.id == activeId,
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInstanceDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Instance'),
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

    void onSave() {
      final name = nameController.text.trim();
      final url = urlController.text.trim();

      if (name.isEmpty || url.isEmpty) return;

      final isValidUrl = Validators.isValidUrl(url);
      if (!isValidUrl) {
        ScaffoldMessenger.of(context).showQuickSnackBar(
          const SnackBar(
            content: Text('Please enter a valid URL (http/https)'),
          ),
        );
        return;
      }

      final newInstance = RemoteInstance(
        id: existingInstance?.id ?? const Uuid().v4(),
        name: name,
        url: url,
        icon: selectedIconState.value.isEmpty ? '🐻' : selectedIconState.value,
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
      title: Text(isEditing ? 'Edit Instance' : 'Add Instance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. maimaiDX)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Webhook URL (http://...)',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Icon:'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}
