import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../../../providers/firmware_provider.dart';
import '../../../providers/hardware_device_provider.dart';
import '../../../services/communication/usb_hinata_impl.dart';

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
        if (isFlashing) ...[
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
              if (device is UsbHinataDeviceImpl) {
                flashNotifier.startFlash(device);
              }
            },
            child: const Text('Retry Update'),
          ),
        ] else if (!(firmware.isLatest ?? false))
          FilledButton.icon(
            onPressed: () {
              final device = deviceState.connectedDevice;
              if (device is UsbHinataDeviceImpl) {
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
}
