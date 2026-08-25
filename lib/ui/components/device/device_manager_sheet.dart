import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

import 'device_switcher_bar.dart';

Future<void> showDeviceManagerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const DeviceManagerSheet(),
  );
}

class DeviceManagerSheet extends ConsumerWidget {
  const DeviceManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final colorScheme = context.colorScheme;
    final l10n = context.l10n;
    final devices = deviceState.devices;
    final activeId = deviceState.activeDeviceId;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: context.mediaQuery.padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.devices_other_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    l10n.connectedDevices,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${devices.length}',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l10n.noDevicesConnected,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final dev = devices.values.elementAt(index);
                  final isSelected = dev.deviceId == activeId;
                  final isConnected = dev.connectionState.value == DeviceConnectionState.connected;
                  final isUsb = dev is UsbHinataDeviceImpl;
                  final pid = isUsb ? (dev as UsbHinataDeviceImpl).productId : null;
                  final String? deviceSvg = pid == 0x0147
                      ? 'assets/std.svg'
                      : pid == 0x0148
                      ? 'assets/lite.svg'
                      : null;

                  return Material(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        ref.read(hardwareDeviceProvider.notifier).selectDevice(dev.deviceId);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primary.withValues(alpha: 0.2)
                                    : colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.all(8),
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
                                      dev.isRemote
                                          ? Icons.cloud_done_rounded
                                          : Icons.usb_rounded,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          dev.displayTitle,
                                          style: context.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            l10n.activeDevice,
                                            style: context.textTheme.labelSmall?.copyWith(
                                              color: colorScheme.onPrimary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dev.alias != null
                                        ? '${dev.productName} • ${isConnected ? "Connected" : "Disconnected"}'
                                        : (isConnected ? 'Connected' : 'Disconnected'),
                                    style: context.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit alias',
                              onPressed: () => showEditDeviceAliasDialog(context, ref, dev),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: l10n.disconnectDevice,
                              onPressed: () {
                                ref.read(hardwareDeviceProvider.notifier).disconnect(dev.deviceId);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await ref.read(hardwareDeviceProvider.notifier).requestUsbDevice();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.pairNewDevice),
                ),
              ),
              if (devices.isNotEmpty) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(hardwareDeviceProvider.notifier).disconnectAll();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(l10n.disconnectAll),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
