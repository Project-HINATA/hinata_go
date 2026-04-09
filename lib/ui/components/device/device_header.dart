import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

class DeviceHeader extends ConsumerWidget {
  final UsbHinataDeviceImpl device;
  const DeviceHeader({required this.device, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final pid = deviceState.productId;
    final String? deviceSvg = pid == 0x0147
        ? 'assets/std.svg'
        : pid == 0x0148
        ? 'assets/lite.svg'
        : null;

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
                      Icons.nfc_rounded,
                      size: 80,
                      color: context.colorScheme.primary,
                    ),
            ),
          ),
          ListTile(
            title: Text(
              device.productName,
              style: context.textTheme.titleLarge,
            ),
            subtitle: Text(
              'Connected via USB - v${deviceState.firmwareVersion ?? "Unknown"}',
            ),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
