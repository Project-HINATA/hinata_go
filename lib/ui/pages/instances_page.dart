import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/remote_instance.dart';
import '../../providers/app_state_provider.dart';
import '../components/instances/instance_item.dart';
import '../components/instances/instance_dialog.dart';

class InstancesPage extends HookConsumerWidget {
  const InstancesPage({super.key});

  void _showInstanceDialog(
    BuildContext context, [
    RemoteInstance? existingInstance,
  ]) {
    showDialog(
      context: context,
      builder: (context) => InstanceDialog(existingInstance: existingInstance),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider);
    final activeId = ref.watch(activeInstanceIdProvider);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(context, instances, activeId),
      ),
      floatingActionButton: _buildFAB(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(title: Text(context.l10n.remoteInstances));
  }

  Widget _buildBody(
    BuildContext context,
    List<RemoteInstance> instances,
    String? activeId,
  ) {
    if (instances.isEmpty) {
      return _buildEmptyState(context);
    }
    return _buildInstancesList(context, instances, activeId);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(child: Text(context.l10n.noInstancesConfigured));
  }

  Widget _buildInstancesList(
    BuildContext context,
    List<RemoteInstance> instances,
    String? activeId,
  ) {
    return ListView.builder(
      itemCount: instances.length,
      itemBuilder: (context, index) {
        final instance = instances[index];
        return _buildInstanceItem(context, instance, instance.id == activeId);
      },
    );
  }

  Widget _buildInstanceItem(
    BuildContext context,
    RemoteInstance instance,
    bool isActive,
  ) {
    return InstanceItem(
      instance: instance,
      isActive: isActive,
      onEdit: () => _showInstanceDialog(context, instance),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showInstanceDialog(context),
      icon: const Icon(Icons.add),
      label: Text(context.l10n.addInstance),
    );
  }
}
