import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

class DeviceSwitcherBar extends ConsumerWidget {
  final Map<String, DeviceInterface> devices;
  final String? activeDeviceId;
  final ValueChanged<String>? onSelectDevice;

  const DeviceSwitcherBar({
    required this.devices,
    required this.activeDeviceId,
    this.onSelectDevice,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;

    return Container(
      height: 76,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final device = devices.values.elementAt(index);
          final isSelected = device.deviceId == activeDeviceId;
          final isConnected =
              device.connectionState.value == DeviceConnectionState.connected;

          return _DeviceSwitcherCard(
            device: device,
            isSelected: isSelected,
            isConnected: isConnected,
            onTap: () {
              if (onSelectDevice != null) {
                onSelectDevice!(device.deviceId);
              } else {
                ref
                    .read(hardwareDeviceProvider.notifier)
                    .selectDevice(device.deviceId);
              }
            },
            onEditAlias: () => showEditDeviceAliasDialog(context, ref, device),
          );
        },
      ),
    );
  }
}

class _DeviceSwitcherCard extends StatelessWidget {
  final DeviceInterface device;
  final bool isSelected;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onEditAlias;

  const _DeviceSwitcherCard({
    required this.device,
    required this.isSelected,
    required this.isConnected,
    required this.onTap,
    required this.onEditAlias,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isUsb = device is UsbHinataDeviceImpl;
    final pid = isUsb ? (device as UsbHinataDeviceImpl).productId : null;
    final String? deviceSvg = pid == 0x0147
        ? 'assets/std.svg'
        : pid == 0x0148
        ? 'assets/lite.svg'
        : null;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: deviceSvg != null
                        ? SvgPicture.asset(
                            deviceSvg,
                            colorFilter: ColorFilter.mode(
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              BlendMode.srcIn,
                            ),
                          )
                        : Icon(
                            device.isRemote
                                ? Icons.cloud_done_rounded
                                : Icons.usb_rounded,
                            size: 20,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayTitle,
                    style: context.textTheme.labelLarge?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    device.alias != null
                        ? device.productName
                        : (isConnected ? 'Connected' : 'Disconnected'),
                    style: context.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: 'Edit alias',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onEditAlias,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showEditDeviceAliasDialog(
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
