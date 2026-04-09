import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../providers/app_state_provider.dart';
import '../../../utils/icon_utils.dart';

class SelectInstanceDialog extends ConsumerWidget {
  const SelectInstanceDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider);
    final activeId = ref.watch(activeInstanceIdProvider);
    final colorScheme = context.colorScheme;

    return AlertDialog(
      title: Text(context.l10n.selectInstance),
      content: SizedBox(
        width: double.maxFinite,
        child: instances.isEmpty
            ? Center(child: Text(context.l10n.noInstances))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: instances.length,
                itemBuilder: (context, index) {
                  final instance = instances[index];
                  final isActive = instance.id == activeId;

                  return ListTile(
                    leading: Text(
                      IconUtils.getEmoji(instance.icon),
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(instance.name),
                    subtitle: Text(
                      instance.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isActive
                        ? Icon(Icons.check_circle, color: colorScheme.primary)
                        : null,
                    onTap: () => context.navigator.pop(instance),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.navigator.pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}
