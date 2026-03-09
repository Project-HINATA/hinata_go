import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/app_update_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final updateState = ref.watch(appUpdateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Secondary Confirmation'),
            subtitle: const Text(
              'Ask for confirmation before sending card data',
            ),
            value: settings.enableSecondaryConfirmation,
            onChanged: (val) {
              ref
                  .read(settingsProvider.notifier)
                  .updateEnableSecondaryConfirmation(val);
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('About'),
            subtitle: Text('HINATA Go v${updateState.currentVersion}'),
            leading: const Icon(Icons.info_outline),
            onTap: () {
              ref.read(appUpdateProvider.notifier).checkUpdate();
            },
          ),
          if (updateState.hasUpdate)
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
                label: Text('UPDATE TO ${updateState.latestVersion}'),
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
