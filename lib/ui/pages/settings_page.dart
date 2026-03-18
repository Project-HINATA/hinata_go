import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/data_management_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/l10n.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final updateState = ref.watch(appUpdateProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.secondaryConfirmation),
            subtitle: Text(l10n.secondaryConfirmationDescription),
            value: settings.enableSecondaryConfirmation,
            onChanged: (val) {
              ref
                  .read(settingsProvider.notifier)
                  .updateEnableSecondaryConfirmation(val);
            },
          ),
          ListTile(
            title: Text(l10n.language),
            subtitle: Text(l10n.languageDescription),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<AppLanguage>(
                value: settings.language,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(settingsProvider.notifier).updateLanguage(value);
                  }
                },
                items: [
                  DropdownMenuItem(
                    value: AppLanguage.system,
                    child: Text(l10n.languageSystem),
                  ),
                  DropdownMenuItem(
                    value: AppLanguage.english,
                    child: Text(l10n.languageEnglishNative),
                  ),
                  DropdownMenuItem(
                    value: AppLanguage.simplifiedChinese,
                    child: Text(l10n.languageChineseNative),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.dataManagement),
            subtitle: Text(l10n.dataManagementDescription),
            leading: const Icon(Icons.import_export),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext sheetContext) {
                  return _DataManagementSheet(parentContext: context);
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.about),
            subtitle: Text('HINATA Go v${updateState.currentVersion}'),
            leading: const Icon(Icons.info_outline),
            onTap: updateState.isUpdateSupported
                ? () {
                    ref.read(appUpdateProvider.notifier).checkUpdate();
                  }
                : null,
          ),
          if (updateState.isUpdateSupported && updateState.hasUpdate)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: () async {
                  if (updateState.downloadUrl != null) {
                    final url = Uri.parse(updateState.downloadUrl!);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                },
                icon: const Icon(Icons.system_update),
                label: Text(l10n.updateToVersion(updateState.latestVersion)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DataManagementSheet extends HookConsumerWidget {
  final BuildContext parentContext;

  const _DataManagementSheet({required this.parentContext});

  Future<void> _handleImport(
    BuildContext sheetContext,
    Future<Map<String, dynamic>?> Function() importMethod,
    DataManagementService dataManagement,
    dynamic l10n,
  ) async {
    Navigator.pop(sheetContext);
    try {
      final data = await importMethod();
      if (data == null) return;

      if (!parentContext.mounted) return;

      final cardsCount = (data['saved_cards'] as List?)?.length ?? 0;
      final foldersCount = (data['card_folders'] as List?)?.length ?? 0;
      final instancesCount = (data['instances'] as List?)?.length ?? 0;

      final result = await showDialog<String>(
        context: parentContext,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.importPreviewTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importPreviewMessage),
              const SizedBox(height: 16),
              Text(l10n.itemCountCards(cardsCount)),
              Text(l10n.itemCountFolders(foldersCount)),
              Text(l10n.itemCountInstances(instancesCount)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              child: Text(l10n.importMerge),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(parentContext).colorScheme.error,
                foregroundColor: Theme.of(parentContext).colorScheme.onError,
              ),
              child: Text(l10n.importOverwrite),
            ),
          ],
        ),
      );

      if (result == 'cancel' || result == null) return;

      if (result == 'overwrite') {
        if (!parentContext.mounted) return;
        final confirmOverwrite = await showDialog<bool>(
          context: parentContext,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.confirmOverwriteTitle),
            content: Text(l10n.confirmOverwriteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(parentContext).colorScheme.error,
                  foregroundColor: Theme.of(parentContext).colorScheme.onError,
                ),
                child: Text(l10n.importOverwrite),
              ),
            ],
          ),
        );
        if (confirmOverwrite != true) return;
      }

      await dataManagement.applyImport(data, merge: result == 'merge');
      if (parentContext.mounted) {
        ScaffoldMessenger.of(
          parentContext,
        ).showSnackBar(SnackBar(content: Text(l10n.importSuccess)));
      }
    } catch (e) {
      final message = e.toString().contains('invalidDataFormat')
          ? l10n.invalidDataFormat
          : e.toString();
      if (parentContext.mounted) {
        ScaffoldMessenger.of(
          parentContext,
        ).showSnackBar(SnackBar(content: Text(l10n.importFailed(message))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final dataManagement = ref.read(dataManagementProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.dataManagement,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(l10n.exportToFile),
            onTap: () async {
              Navigator.pop(context);
              try {
                await dataManagement.exportToFile();
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(
                    parentContext,
                  ).showSnackBar(SnackBar(content: Text(l10n.exportSuccess)));
                }
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(content: Text(l10n.exportFailed(e.toString()))),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: Text(l10n.exportToClipboard),
            onTap: () async {
              Navigator.pop(context);
              try {
                await dataManagement.exportToClipboard();
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(
                    parentContext,
                  ).showSnackBar(SnackBar(content: Text(l10n.exportSuccess)));
                }
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(content: Text(l10n.exportFailed(e.toString()))),
                  );
                }
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(l10n.importFromFile),
            onTap: () {
              _handleImport(
                context,
                dataManagement.importFromFile,
                dataManagement,
                l10n,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: Text(l10n.importFromClipboard),
            onTap: () {
              _handleImport(
                context,
                dataManagement.importFromClipboard,
                dataManagement,
                l10n,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
