import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/hardware_device_provider.dart';
import '../../services/communication/usb_hinata_impl.dart';
import '../components/device/disconnected_state.dart';
import '../components/device/device_dashboard.dart';

class DeviceControlPage extends ConsumerWidget {
  const DeviceControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final isConnected = deviceState.connectedDevice != null;
    final isUsbHinata = deviceState.connectedDevice is UsbHinataDeviceImpl;
    final hinataDevice = isUsbHinata
        ? deviceState.connectedDevice as UsbHinataDeviceImpl
        : null;

    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deviceHub),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: () {
                ref.read(hardwareDeviceProvider.notifier).disconnect();
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isConnected && hinataDevice != null
              ? DeviceDashboard(
                  device: hinataDevice,
                  key: ValueKey(hinataDevice.deviceId),
                )
              : const DisconnectedState(),
        ),
      ),
      floatingActionButton: !isConnected
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                ref.read(hardwareDeviceProvider.notifier).disconnect();
              },
              tooltip: 'Disconnect',
              child: const Icon(Icons.link_off),
            ),
    );
  }
}
