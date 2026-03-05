import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';

class InstancesPage extends ConsumerStatefulWidget {
  const InstancesPage({super.key});

  @override
  ConsumerState<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends ConsumerState<InstancesPage> {
  void _showInstanceDialog([RemoteInstance? existingInstance]) {
    final isEditing = existingInstance != null;
    final nameController = TextEditingController(text: existingInstance?.name);
    final urlController = TextEditingController(text: existingInstance?.url);
    final iconController = TextEditingController(
      text: existingInstance?.icon ?? 'dns',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Instance' : 'Add Instance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (e.g. Home Server)',
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
              TextField(
                controller: iconController,
                decoration: const InputDecoration(
                  labelText: 'Icon Name (e.g. dns, home)',
                ),
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
                if (nameController.text.isNotEmpty &&
                    urlController.text.isNotEmpty) {
                  final newInstance = RemoteInstance(
                    id: isEditing ? existingInstance.id : const Uuid().v4(),
                    name: nameController.text,
                    url: urlController.text,
                    icon: iconController.text.isEmpty
                        ? 'dns'
                        : iconController.text,
                  );

                  if (isEditing) {
                    ref
                        .read(instancesProvider.notifier)
                        .updateInstance(newInstance);
                  } else {
                    ref
                        .read(instancesProvider.notifier)
                        .addInstance(newInstance);
                    // auto select if it's the first one
                    if (ref.read(instancesProvider).length == 1) {
                      ref
                          .read(activeInstanceIdProvider.notifier)
                          .setActiveId(newInstance.id);
                    }
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'cloud':
        return Icons.cloud;
      case 'computer':
        return Icons.computer;
      case 'api':
        return Icons.api;
      case 'webhook':
        return Icons.webhook;
      default:
        return Icons.dns;
    }
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
          child: Icon(
            _getIconData(instance.icon),
            color: isActive ? colorScheme.primary : null,
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
        onTap: () {
          ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${instance.name} is now active')),
          );
        },
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
