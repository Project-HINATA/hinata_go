import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/app_update_state.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';
import '../app_layout.dart';
import '../components/settings/data_management_sheet.dart';
import '../widgets/app_scaffold.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final settings = ref.watch(settingsProvider);
    final updateState = ref.watch(appUpdateProvider);

    return AppScaffold(
      title: l10n.settings,
      showMaterialAppBar: !layout.isLandscape,
      body: SafeArea(
        top: layout.isLandscape,
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
              githubItem: _buildExternalLinkItem(
                title: l10n.github,
                icon: Icons.code_rounded,
                url: AppConstants.githubUrl,
              ),
              prismItem: _buildExternalLinkItem(
                title: l10n.prism,
                icon: Icons.link,
                url: AppConstants.prismUrl,
              ),
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

  Widget _buildExpirationSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    const options = [5, 10, 15, 30, 60];
    void select(int value) {
      ref.read(settingsProvider.notifier).updateCardExpirationSeconds(value);
    }

    return ListTile(
      title: Text(l10n.cardExpiration),
      subtitle: Text(l10n.cardExpirationDescription),
      trailing: useCupertinoChrome
          ? _NativeMenuSelector<int>(
              options: options,
              selected: settings.cardExpirationSeconds,
              labelOf: (value) => l10n.cardExpirationValue(value.toString()),
              onSelected: select,
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: settings.cardExpirationSeconds,
                onChanged: (value) {
                  if (value != null) select(value);
                },
                items: options.map((int val) {
                  return DropdownMenuItem<int>(
                    value: val,
                    child: Text(l10n.cardExpirationValue(val.toString())),
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
    String labelOf(AppLanguage language) => switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.english => l10n.languageEnglishNative,
      AppLanguage.simplifiedChinese => l10n.languageChineseNative,
    };
    void select(AppLanguage value) {
      ref.read(settingsProvider.notifier).updateLanguage(value);
    }

    return ListTile(
      title: Text(l10n.language),
      subtitle: Text(l10n.languageDescription),
      trailing: useCupertinoChrome
          ? _NativeMenuSelector<AppLanguage>(
              options: AppLanguage.values,
              selected: settings.language,
              labelOf: labelOf,
              onSelected: select,
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<AppLanguage>(
                value: settings.language,
                onChanged: (value) {
                  if (value != null) select(value);
                },
                items: [
                  for (final language in AppLanguage.values)
                    DropdownMenuItem(
                      value: language,
                      child: Text(labelOf(language)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildDataManagementItem(BuildContext context) {
    return ListTile(
      title: Text(l10n.dataManagement),
      subtitle: Text(l10n.dataManagementDescription),
      leading: const Icon(Icons.import_export),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const DataManagementSheet(),
              ),
            );
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
      title: Text(l10n.about),
      subtitle: Text(updateState.versionDisplay),
      leading: const Icon(Icons.info_outline),
      onTap: updateState.isUpdateSupported
          ? () {
              ref.read(appUpdateProvider.notifier).checkUpdate();
            }
          : null,
    );
  }

  Widget _buildExternalLinkItem({
    required String title,
    required IconData icon,
    required String url,
  }) {
    return ListTile(
      title: Text(title),
      leading: Icon(icon),
      trailing: const Icon(Icons.open_in_new),
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  Widget _buildUpdateActionButton(
    BuildContext context,
    AppUpdateState updateState,
  ) {
    final platform = defaultTargetPlatform;
    final githubUrl = updateState.downloadUrl ?? AppConstants.githubReleasesUrl;

    if (platform == TargetPlatform.android) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final url = Uri.parse(githubUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.code_rounded),
                label: Text(l10n.updateViaGithub),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final url = Uri.parse(AppConstants.googlePlayUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.shop_outlined),
                label: Text(l10n.updateViaGooglePlay),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
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

    if (platform == TargetPlatform.iOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: FilledButton.icon(
          onPressed: () async {
            final url = Uri.parse(AppConstants.appStoreUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.apple),
          label: Text(l10n.updateViaAppStore),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FilledButton.icon(
        onPressed: () async {
          final url = Uri.parse(githubUrl);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
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
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.expirationSettings,
    required this.languageSelector,
    required this.dataManagementItem,
    required this.aboutItem,
    required this.githubItem,
    required this.prismItem,
    required this.updateActionButton,
  });

  final Widget expirationSettings;
  final Widget languageSelector;
  final Widget dataManagementItem;
  final Widget aboutItem;
  final Widget githubItem;
  final Widget prismItem;
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
        githubItem,
        prismItem,
        ...(updateActionButton == null ? const [] : [updateActionButton!]),
      ],
    );
  }
}

/// A pull-down button that picks one value from a native iOS menu, with the
/// current choice checked.
class _NativeMenuSelector<T> extends StatelessWidget {
  const _NativeMenuSelector({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return AdaptivePopupMenuButton.text<T>(
      label: labelOf(selected),
      buttonStyle: PopupButtonStyle.plain,
      shrinkWrap: true,
      items: [
        for (final option in options)
          AdaptivePopupMenuItem<T>(
            label: labelOf(option),
            value: option,
            selected: option == selected,
          ),
      ],
      onSelected: (index, item) => onSelected(item.value as T),
    );
  }
}
