import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../context_extensions.dart';
import '../../../../models/remote_instance.dart';
import '../../../../providers/app_state_provider.dart';
import '../../../../services/communication/device_interface.dart';
import '../../../../services/communication/remote_hinata_impl.dart';
import '../../../../utils/icon_utils.dart';
import '../../../components/instances/instance_dialog.dart';

class InstanceSelectorBar extends ConsumerWidget {
  final RemoteHinataDeviceImpl? activeDevice;

  const InstanceSelectorBar({
    super.key,
    this.activeDevice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider);
    final activeId = ref.watch(activeInstanceIdProvider);
    final l10n = context.l10n;

    if (instances.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.router_outlined, color: context.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.noInstancesHint,
                  style: context.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openAddDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.addInstance),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: instances.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == instances.length) {
            return Center(
              child: IconButton.filledTonal(
                tooltip: l10n.addInstance,
                icon: const Icon(Icons.add),
                onPressed: () => _openAddDialog(context),
              ),
            );
          }

          final instance = instances[index];
          final isSelected = instance.id == activeId;

          return Center(
            child: _InstanceChip(
              instance: instance,
              isSelected: isSelected,
              activeDevice: isSelected ? activeDevice : null,
              onTap: () {
                ref.read(activeInstanceIdProvider.notifier).setActiveId(instance.id);
              },
              onLongPress: () => _openEditDialog(context, instance),
            ),
          );
        },
      ),
    );
  }

  void _openAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const InstanceDialog(),
    );
  }

  void _openEditDialog(BuildContext context, RemoteInstance instance) {
    showDialog(
      context: context,
      builder: (context) => InstanceDialog(existingInstance: instance),
    );
  }
}

class _InstanceChip extends StatelessWidget {
  final RemoteInstance instance;
  final bool isSelected;
  final RemoteHinataDeviceImpl? activeDevice;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _InstanceChip({
    required this.instance,
    required this.isSelected,
    this.activeDevice,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emoji = IconUtils.getEmoji(instance.icon);

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 1.5)
            : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                instance.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
              if (isSelected && activeDevice != null) ...[
                const SizedBox(width: 8),
                _ConnectionIndicator(device: activeDevice!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final RemoteHinataDeviceImpl device;

  const _ConnectionIndicator({required this.device});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DeviceConnectionState>(
      valueListenable: device.connectionState,
      builder: (context, state, _) {
        final (color, tooltip) = switch (state) {
          DeviceConnectionState.connected => (Colors.green, context.l10n.online),
          DeviceConnectionState.connecting => (Colors.amber, context.l10n.connecting),
          DeviceConnectionState.error => (Colors.red, context.l10n.offline),
          DeviceConnectionState.disconnected => (Colors.grey, context.l10n.offline),
        };

        return Tooltip(
          message: tooltip,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
