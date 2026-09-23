import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/firmware_provider.dart';
import '../../../providers/hardware_device_provider.dart';

class FirmwareStatusView extends ConsumerWidget {
  const FirmwareStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!firmwareFeatureEnabled) {
      return Text(
        'Firmware updates are not available in this build.',
        style: context.textTheme.bodyLarge,
        textAlign: TextAlign.center,
      );
    }

    final firmState = ref.watch(firmwareProvider);
    final flashNotifier = ref.read(firmwareProvider.notifier);
    final deviceState = ref.watch(hardwareDeviceProvider);
    final firmware = firmState.firmware;

    final isFlashing = firmState.isFlashing;
    final l10n = context.l10n;

    if (firmState.isRequesting) {
      return const CircularProgressIndicator();
    }

    if (firmware == null) {
      return const Text('Failed to check firmware status.');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          (firmware.isLatest ?? false)
              ? Icons.check_circle_outline
              : Icons.system_update,
          size: 100,
          color: (firmware.isLatest ?? false)
              ? Colors.green
              : context.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          (firmware.isLatest ?? false)
              ? 'Your device is up to date!'
              : 'Update Available',
          style: context.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (!(firmware.isLatest ?? false)) ...[
          Text('Latest Version: ${firmware.version ?? "Unknown"}'),
          const SizedBox(height: 16),
          Text(
            firmware.message ?? '',
            style: context.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 48),
        if (kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            !isFlashing &&
            !(firmware.isLatest ?? false))
          _buildWindowsWebNotice(context, l10n)
        else if (isFlashing) ...[
          Text(firmState.statusText),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: firmState.progress),
        ] else if (firmState.flashError != null) ...[
          Text(
            'Error: ${firmState.flashError}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              final device = deviceState.connectedDevice;
              if (device != null) {
                flashNotifier.startFlash(device);
              }
            },
            child: const Text('Retry Update'),
          ),
        ] else if (!(firmware.isLatest ?? false))
          FilledButton.icon(
            onPressed: () {
              final device = deviceState.connectedDevice;
              if (device != null) {
                flashNotifier.startFlash(device);
              }
            },
            icon: const Icon(Icons.flash_on),
            label: const Text('Start Update'),
            style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
          ),
      ],
    );
  }

  Widget _buildWindowsWebNotice(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.windowsFirmwareUpdateUnavailable,
          style: context.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(
              'https://github.com/Project-HINATA/hinata_client-pub/releases/latest',
            ),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.openHinataClient),
        ),
      ],
    );
  }
}
