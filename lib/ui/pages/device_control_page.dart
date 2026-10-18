import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/hardware_device_provider.dart';
import '../components/device/disconnected_state.dart';
import '../components/device/device_dashboard.dart';
import '../widgets/app_scaffold.dart';

class DeviceControlPage extends ConsumerWidget {
  const DeviceControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final hinataDevice = deviceState.connectedDevice;
    final isConnected = hinataDevice != null;

    void disconnect() => ref.read(hardwareDeviceProvider.notifier).disconnect();

    return AppScaffold(
      title: l10n.deviceHub,
      actions: [
        if (isConnected)
          AdaptiveAppBarAction(
            iosSymbol: 'link.badge.minus',
            icon: Icons.link_off,
            label: 'Disconnect',
            onPressed: disconnect,
          ),
      ],
      body: SafeArea(
        top: useCupertinoChrome,
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: hinataDevice != null
              ? DeviceDashboard(
                  device: hinataDevice,
                  key: ValueKey(hinataDevice.deviceId),
                )
              : const DisconnectedState(),
        ),
      ),
      materialFloatingActionButton: !isConnected
          ? null
          : FloatingActionButton.small(
              onPressed: disconnect,
              tooltip: 'Disconnect',
              child: const Icon(Icons.link_off),
            ),
    );
  }
}
