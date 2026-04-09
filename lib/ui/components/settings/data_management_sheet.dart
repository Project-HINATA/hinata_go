import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/context_extensions.dart';

import '../../../providers/data_management_provider.dart';
import '../../../services/notification_service.dart';

class DataManagementSheet extends HookConsumerWidget {
  final BuildContext parentContext;

  const DataManagementSheet({super.key, required this.parentContext});

  Future<void> _handleImport(
    BuildContext sheetContext,
    WidgetRef ref,
    Future<Map<String, dynamic>?> Function() importMethod,
    DataManagementService dataManagement,
  ) async {
    final l10n = parentContext.l10n;
    sheetContext.navigator.pop();
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
              onPressed: () => dialogContext.navigator.pop('cancel'),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => dialogContext.navigator.pop('merge'),
              child: Text(l10n.importMerge),
            ),
            FilledButton(
              onPressed: () => dialogContext.navigator.pop('overwrite'),
              style: FilledButton.styleFrom(
                backgroundColor: parentContext.colorScheme.error,
                foregroundColor: parentContext.colorScheme.onError,
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
                onPressed: () => dialogContext.navigator.pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => dialogContext.navigator.pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: parentContext.colorScheme.error,
                  foregroundColor: parentContext.colorScheme.onError,
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
        ref.read(notificationServiceProvider).showSuccess(l10n.importSuccess);
      }
    } catch (e) {
      final message = e.toString().contains('invalidDataFormat')
          ? l10n.invalidDataFormat
          : e.toString();
      if (parentContext.mounted) {
        ref
            .read(notificationServiceProvider)
            .showError(l10n.importFailed(message));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataManagement = ref.read(dataManagementProvider);

    return SafeArea(
      child: _DataManagementSheetBody(
        header: _buildHeader(context),
        exportFileItem: _buildExportFileItem(context, ref, dataManagement),
        exportClipboardItem: _buildExportClipboardItem(
          context,
          ref,
          dataManagement,
        ),
        importFileItem: _buildImportFileItem(context, ref, dataManagement),
        importClipboardItem: _buildImportClipboardItem(
          context,
          ref,
          dataManagement,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ListTile(
      title: Text(
        context.l10n.dataManagement,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildExportFileItem(
    BuildContext context,
    WidgetRef ref,
    DataManagementService dataManagement,
  ) {
    return _DataManagementTile(
      leading: const Icon(Icons.upload_file),
      title: Text(context.l10n.exportToFile),
      onTap: () async {
        context.navigator.pop();
        try {
          await dataManagement.exportToFile();
          if (parentContext.mounted) {
            ref
                .read(notificationServiceProvider)
                .showSuccess(context.l10n.exportSuccess);
          }
        } catch (e) {
          if (parentContext.mounted) {
            ref
                .read(notificationServiceProvider)
                .showError(context.l10n.exportFailed(e.toString()));
          }
        }
      },
    );
  }

  Widget _buildExportClipboardItem(
    BuildContext context,
    WidgetRef ref,
    DataManagementService dataManagement,
  ) {
    return _DataManagementTile(
      leading: const Icon(Icons.content_copy),
      title: Text(context.l10n.exportToClipboard),
      onTap: () async {
        context.navigator.pop();
        try {
          await dataManagement.exportToClipboard();
          if (parentContext.mounted) {
            ref
                .read(notificationServiceProvider)
                .showSuccess(context.l10n.exportSuccess);
          }
        } catch (e) {
          if (parentContext.mounted) {
            ref
                .read(notificationServiceProvider)
                .showError(context.l10n.exportFailed(e.toString()));
          }
        }
      },
    );
  }

  Widget _buildImportFileItem(
    BuildContext context,
    WidgetRef ref,
    DataManagementService dataManagement,
  ) {
    return _DataManagementTile(
      leading: const Icon(Icons.file_download),
      title: Text(context.l10n.importFromFile),
      onTap: () => _handleImport(
        context,
        ref,
        dataManagement.importFromFile,
        dataManagement,
      ),
    );
  }

  Widget _buildImportClipboardItem(
    BuildContext context,
    WidgetRef ref,
    DataManagementService dataManagement,
  ) {
    return _DataManagementTile(
      leading: const Icon(Icons.content_paste),
      title: Text(context.l10n.importFromClipboard),
      onTap: () => _handleImport(
        context,
        ref,
        dataManagement.importFromClipboard,
        dataManagement,
      ),
    );
  }
}

class _DataManagementSheetBody extends StatelessWidget {
  const _DataManagementSheetBody({
    required this.header,
    required this.exportFileItem,
    required this.exportClipboardItem,
    required this.importFileItem,
    required this.importClipboardItem,
  });

  final Widget header;
  final Widget exportFileItem;
  final Widget exportClipboardItem;
  final Widget importFileItem;
  final Widget importClipboardItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        exportFileItem,
        exportClipboardItem,
        const Divider(),
        importFileItem,
        importClipboardItem,
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DataManagementTile extends StatelessWidget {
  const _DataManagementTile({
    required this.leading,
    required this.title,
    required this.onTap,
  });

  final Widget leading;
  final Widget title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: leading, title: title, onTap: onTap);
  }
}
