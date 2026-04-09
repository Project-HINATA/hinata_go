import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../models/remote_instance.dart';
import '../../../providers/app_state_provider.dart';
import '../../../services/notification_service.dart';
import '../../../utils/icon_utils.dart';

class InstanceItem extends ConsumerWidget {
  final RemoteInstance instance;
  final bool isActive;
  final VoidCallback onEdit;

  const InstanceItem({
    super.key,
    required this.instance,
    required this.isActive,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;

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
        leading: _buildLeading(colorScheme),
        title: _buildTitle(),
        subtitle: _buildSubtitle(),
        trailing: _buildTrailing(),
        onTap: () => _onTap(context, ref),
      ),
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

  Widget _buildLeading(ColorScheme colorScheme) {
    return CircleAvatar(
      backgroundColor: isActive
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      child: Text(
        IconUtils.getEmoji(instance.icon),
        style: const TextStyle(fontSize: 24),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      instance.name,
      style: TextStyle(
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(instance.url, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _buildTrailing() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isActive)
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Icon(Icons.check_circle, color: Colors.green),
          ),
        IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
      ],
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
    ref
        .read(notificationServiceProvider)
        .showSuccess(context.l10n.instanceNowActive(instance.name));
  }
}
