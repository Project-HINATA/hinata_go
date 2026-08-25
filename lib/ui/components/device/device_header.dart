import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

class DeviceHeader extends ConsumerWidget {
  final DeviceInterface device;
  const DeviceHeader({required this.device, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final isUsb = device is UsbHinataDeviceImpl;
    final pid = isUsb
        ? (device as UsbHinataDeviceImpl).productId
        : deviceState.productId;
    final String? deviceSvg = pid == 0x0147
        ? 'assets/std.svg'
        : pid == 0x0148
        ? 'assets/lite.svg'
        : null;

    final String subtitleText;
    if (isUsb) {
      final usb = device as UsbHinataDeviceImpl;
      subtitleText =
          'Connected via USB - v${usb.firmVersion.isNotEmpty ? usb.firmVersion : (deviceState.firmwareVersion ?? "Unknown")}';
    } else if (device.isRemote) {
      subtitleText = 'Connected via Remote (${device.instanceId ?? "AimeIO"})';
    } else {
      final status =
          device.connectionState.value == DeviceConnectionState.connected
              ? 'Connected'
              : 'Disconnected';
      subtitleText = '$status (${device.deviceId})';
    }

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            color: context.colorScheme.surfaceContainerHighest,
            child: Center(
              child: deviceSvg != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SvgPicture.asset(
                        deviceSvg,
                        fit: BoxFit.contain,
                        colorFilter: ColorFilter.mode(
                          context.colorScheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                    )
                  : Icon(
                      device.isRemote
                          ? Icons.cloud_done_rounded
                          : Icons.nfc_rounded,
                      size: 80,
                      color: context.colorScheme.primary,
                    ),
            ),
          ),
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    device.displayTitle,
                    style: context.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Rename alias',
                  onPressed: () => _showEditAliasDialog(context, ref, device),
                ),
              ],
            ),
            subtitle: Text(subtitleText),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditAliasDialog(
    BuildContext context,
    WidgetRef ref,
    DeviceInterface device,
  ) async {
    final controller = TextEditingController(text: device.alias ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device Alias'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Alias / Name',
            hintText: device.productName,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => controller.clear(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      ref
          .read(hardwareDeviceProvider.notifier)
          .setDeviceAlias(device.deviceId, result);
    }
  }
}
