import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../context_extensions.dart';
import '../../../models/remote_instance.dart';
import '../../../providers/app_state_provider.dart';
import '../../app_layout.dart';
import 'components/instance_selector_bar.dart';
import 'components/io_config_card.dart';
import 'components/quick_actions_card.dart';
import 'components/remote_reader_card.dart';

class RemotePage extends HookConsumerWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final l10n = context.l10n;

    final instances = ref.watch(instancesProvider);
    final activeInstance = ref.watch(activeInstanceProvider);
    final activeRemoteDevice = ref.watch(activeRemoteDeviceProvider);

    return Scaffold(
      appBar: layout.isLandscape
          ? null
          : AppBar(
              title: Text(l10n.remoteHub),
            ),
      body: SafeArea(
        top: layout.isLandscape,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Instance selector bar at the top
                InstanceSelectorBar(activeDevice: activeRemoteDevice),

                // 2. Main content area
                Expanded(
                  child: instances.isEmpty
                      ? _buildEmptyInstancesView(context)
                      : activeInstance == null
                          ? _buildNoSelectionView(context)
                          : _buildActiveInstanceContent(
                              context,
                              activeInstance,
                              activeRemoteDevice,
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyInstancesView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.router_outlined,
              size: 64,
              color: context.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.noInstancesHint,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyLarge?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSelectionView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: context.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.noActiveInstanceSelectedTap,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveInstanceContent(
    BuildContext context,
    RemoteInstance activeInstance,
    dynamic activeRemoteDevice,
  ) {
    final isHinataIo = activeInstance.type == InstanceType.hinataIo;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Quick Actions Card (Card swipe + virtual controls)
        QuickActionsCard(
          key: ValueKey('quick_actions_${activeInstance.id}'),
          activeInstance: activeInstance,
          activeDevice: isHinataIo ? activeRemoteDevice : null,
        ),
        const SizedBox(height: 16),

        if (isHinataIo) ...[
          // IO Configuration Card
          IoConfigCard(
            key: ValueKey('io_config_${activeInstance.id}'),
            remoteDevice: activeRemoteDevice,
          ),
          const SizedBox(height: 16),

          // Attached Physical Reader Hardware Card
          RemoteReaderCard(
            key: ValueKey('remote_reader_${activeInstance.id}'),
            remoteDevice: activeRemoteDevice,
          ),
        ] else ...[
          // Non-HinataIO (e.g. SpiceAPI) notice card
          Card(
            elevation: 0,
            color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: context.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${activeInstance.type.name.toUpperCase()} mode active. IO config and hardware reader management are supported on HINATA IO instances.',
                      style: context.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
