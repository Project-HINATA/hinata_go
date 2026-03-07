import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/validators.dart';
import '../../utils/icon_utils.dart';
import '../../utils/snackbar_utils.dart';

class InstancesPage extends ConsumerStatefulWidget {
  const InstancesPage({super.key});

  @override
  ConsumerState<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends ConsumerState<InstancesPage> {
  void _showInstanceDialog([RemoteInstance? existingInstance]) {
    showDialog(
      context: context,
      builder: (context) => _InstanceDialog(existingInstance: existingInstance),
    );
  }

  void _onDismissInstance(RemoteInstance instance, bool isActive) {
    if (isActive) {
      ref.read(activeInstanceIdProvider.notifier).setActiveId(null);
    }
    ref.read(instancesProvider.notifier).removeInstance(instance.id);
  }

  void _onTapInstance(RemoteInstance instance) {
    ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(content: Text('${instance.name} is now active')),
    );
  }
  // ---------------------------------------------------------------------------
  // Builder methods
  // ---------------------------------------------------------------------------

  /// Swipe-to-delete background.
  Widget _buildDismissBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  /// A single instance list item.
  Widget _buildInstanceItem(RemoteInstance instance, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(instance.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) => _onDismissInstance(instance, isActive),
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
              onPressed: () => _showInstanceDialog(instance),
            ),
          ],
        ),
        onTap: () => _onTapInstance(instance),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
                return _buildInstanceItem(instance, instance.id == activeId);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInstanceDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Instance'),
      ),
    );
  }
}

class _InstanceDialog extends ConsumerStatefulWidget {
  final RemoteInstance? existingInstance;
  const _InstanceDialog({this.existingInstance});

  @override
  ConsumerState<_InstanceDialog> createState() => _InstanceDialogState();
}

class _InstanceDialogState extends ConsumerState<_InstanceDialog> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late String _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingInstance?.name,
    );
    _urlController = TextEditingController(text: widget.existingInstance?.url);
    _selectedIcon = widget.existingInstance?.icon ?? '🐻';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) return;

    final isValidUrl = Validators.isValidUrl(url);
    if (!isValidUrl) {
      ScaffoldMessenger.of(context).showQuickSnackBar(
        const SnackBar(content: Text('Please enter a valid URL (http/https)')),
      );
      return;
    }

    final newInstance = RemoteInstance(
      id: widget.existingInstance?.id ?? const Uuid().v4(),
      name: name,
      url: url,
      icon: _selectedIcon.isEmpty ? '🐻' : _selectedIcon,
    );

    if (widget.existingInstance != null) {
      ref.read(instancesProvider.notifier).updateInstance(newInstance);
    } else {
      ref.read(instancesProvider.notifier).addInstance(newInstance);
      if (ref.read(instancesProvider).length == 1) {
        ref.read(activeInstanceIdProvider.notifier).setActiveId(newInstance.id);
      }
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingInstance != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Instance' : 'Add Instance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name (e.g. maimaiDX)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
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
              final isSelected = iconName == _selectedIcon;
              return ChoiceChip(
                label: Text(
                  IconUtils.getEmoji(iconName),
                  style: const TextStyle(fontSize: 24),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedIcon = iconName;
                    });
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Save')),
      ],
    );
  }
}
