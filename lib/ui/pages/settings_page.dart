import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/app_update_state.dart';
import '../../providers/settings_provider.dart';
import '../app_layout.dart';
import '../components/settings/data_management_sheet.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final settings = ref.watch(settingsProvider);
    final updateState = ref.watch(appUpdateProvider);

    return Scaffold(
      appBar: layout.showPageAppBar ? _buildAppBar(context) : null,
      body: SafeArea(
        top: !layout.showPageAppBar,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _SettingsList(
              expirationSettings: _buildExpirationSettings(
                context,
                ref,
                settings,
              ),
              languageSelector: _buildLanguageSelector(context, ref, settings),
              dataManagementItem: _buildDataManagementItem(context),
              aboutItem: _buildAboutItem(context, ref, updateState),
              updateActionButton:
                  updateState.isUpdateSupported && updateState.hasUpdate
                  ? _buildUpdateActionButton(context, updateState)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(title: Text(context.l10n.settings));
  }

  Widget _buildExpirationSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return ListTile(
      title: Text(context.l10n.cardExpiration),
      subtitle: Text(context.l10n.cardExpirationDescription),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: settings.cardExpirationSeconds,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(settingsProvider.notifier)
                  .updateCardExpirationSeconds(value);
            }
          },
          items: [5, 10, 15, 30, 60].map((int val) {
            return DropdownMenuItem<int>(
              value: val,
              child: Text(context.l10n.cardExpirationValue(val.toString())),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return ListTile(
      title: Text(context.l10n.language),
      subtitle: Text(context.l10n.languageDescription),
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
              child: Text(context.l10n.languageSystem),
            ),
            DropdownMenuItem(
              value: AppLanguage.english,
              child: Text(context.l10n.languageEnglishNative),
            ),
            DropdownMenuItem(
              value: AppLanguage.simplifiedChinese,
              child: Text(context.l10n.languageChineseNative),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataManagementItem(BuildContext context) {
    return ListTile(
      title: Text(context.l10n.dataManagement),
      subtitle: Text(context.l10n.dataManagementDescription),
      leading: const Icon(Icons.import_export),
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (BuildContext sheetContext) {
            return DataManagementSheet(parentContext: context);
          },
        );
      },
    );
  }

  Widget _buildAboutItem(
    BuildContext context,
    WidgetRef ref,
    AppUpdateState updateState,
  ) {
    return ListTile(
      title: Text(context.l10n.about),
      subtitle: Text('HINATA Go v${updateState.currentVersion}'),
      leading: const Icon(Icons.info_outline),
      onTap: updateState.isUpdateSupported
          ? () {
              ref.read(appUpdateProvider.notifier).checkUpdate();
            }
          : null,
    );
  }

  Widget _buildUpdateActionButton(
    BuildContext context,
    AppUpdateState updateState,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FilledButton.icon(
        onPressed: () async {
          if (updateState.downloadUrl != null) {
            final url = Uri.parse(updateState.downloadUrl!);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          }
        },
        icon: const Icon(Icons.system_update),
        label: Text(context.l10n.updateToVersion(updateState.latestVersion)),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.expirationSettings,
    required this.languageSelector,
    required this.dataManagementItem,
    required this.aboutItem,
    required this.updateActionButton,
  });

  final Widget expirationSettings;
  final Widget languageSelector;
  final Widget dataManagementItem;
  final Widget aboutItem;
  final Widget? updateActionButton;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        expirationSettings,
        languageSelector,
        const Divider(),
        dataManagementItem,
        const Divider(),
        aboutItem,
        ...(updateActionButton == null ? const [] : [updateActionButton!]),
      ],
    );
  }
}
