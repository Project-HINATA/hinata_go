import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/app_update_provider.dart';
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
