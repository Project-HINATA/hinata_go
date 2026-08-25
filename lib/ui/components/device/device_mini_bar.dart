import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

import 'device_dashboard.dart';
import 'device_switcher_bar.dart';
import 'disconnected_state.dart';

bool shouldShowBottomFloatingDeviceBar(
  BuildContext context, {
  required bool hidAvailable,
  bool hasConnectedDevices = false,
}) {
  return hidAvailable || hasConnectedDevices;
}

class DeviceMiniBar extends ConsumerWidget {
  final bool compact;
  final bool railExpanded;

  const DeviceMiniBar({
    this.compact = false,
    this.railExpanded = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(hardwareDeviceProvider);
    final displayData = _DeviceMiniBarDisplayData.fromState(
      context,
      deviceState,
    );

    if (displayData.hideOnCurrentPlatform) return const SizedBox.shrink();

    if (compact) {
      return Tooltip(
        message: displayData.title,
        child: _CompactDeviceMiniBar(
          isConnected: displayData.isConnected,
          deviceCount: displayData.deviceCount,
          deviceSvg: displayData.deviceSvg,
          colorScheme: displayData.colorScheme,
          onTap: () => _showDeviceSheet(context),
        ),
      );
    }

    if (railExpanded) {
      return _RailExpandedDeviceMiniBar(
        isConnected: displayData.isConnected,
        deviceCount: displayData.deviceCount,
        deviceSvg: displayData.deviceSvg,
        colorScheme: displayData.colorScheme,
        title: displayData.title,
        subtitle: displayData.subtitle,
        onTap: () => _showDeviceSheet(context),
      );
    }

    return _FullDeviceMiniBar(
      displayData: displayData,
      onTap: () => _showDeviceSheet(context),
      onDisconnect: displayData.isConnected
          ? () => ref.read(hardwareDeviceProvider.notifier).disconnect()
          : null,
    );
  }

  void _showDeviceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Consumer(
            builder: (context, ref, child) {
              return _DeviceSheetContent(
                state: ref.watch(hardwareDeviceProvider),
                scrollController: scrollController,
              );
            },
          );
        },
      ),
    );
  }
}

class _DeviceMiniBarDisplayData {
  const _DeviceMiniBarDisplayData({
    required this.isConnected,
    required this.deviceCount,
    required this.hideOnCurrentPlatform,
    required this.title,
    required this.subtitle,
    required this.deviceSvg,
    required this.colorScheme,
  });

  factory _DeviceMiniBarDisplayData.fromState(
    BuildContext context,
    HardwareDeviceState deviceState,
  ) {
    final l10n = context.l10n;
    final theme = context.theme;
    final deviceCount = deviceState.devices.length;
    final isConnected = deviceCount > 0;
    final activeDevice = deviceState.activeDevice;

    final String title;
    final String subtitle;
    if (!isConnected) {
      title = l10n.noDeviceConnected;
      subtitle = l10n.tapToConnect;
    } else if (deviceCount > 1) {
      title = '$deviceCount Devices Connected';
      subtitle = 'Active: ${activeDevice?.displayTitle ?? "None"}';
    } else {
      title =
          activeDevice?.displayTitle ??
          (activeDevice?.productName ?? l10n.deviceHub);
      if (activeDevice is UsbHinataDeviceImpl) {
        subtitle = l10n.firmwareVersion(deviceState.firmwareVersion ?? '...');
      } else if (activeDevice?.isRemote == true) {
        subtitle = 'Remote AimeIO';
      } else {
        subtitle = 'Connected';
      }
    }

    final deviceSvg = deviceCount == 1
        ? switch (deviceState.productId) {
            0x0147 => 'assets/std.svg',
            0x0148 => 'assets/lite.svg',
            _ => null,
          }
        : null;

    return _DeviceMiniBarDisplayData(
      isConnected: isConnected,
      deviceCount: deviceCount,
      hideOnCurrentPlatform: !shouldShowBottomFloatingDeviceBar(
        context,
        hidAvailable: deviceState.hidAvailable,
        hasConnectedDevices: isConnected,
      ),
      title: title,
      subtitle: subtitle,
      deviceSvg: deviceSvg,
      colorScheme: theme.colorScheme,
    );
  }

  final bool isConnected;
  final int deviceCount;
  final bool hideOnCurrentPlatform;
  final String title;
  final String subtitle;
  final String? deviceSvg;
  final ColorScheme colorScheme;
}

class _FullDeviceMiniBar extends StatelessWidget {
  const _FullDeviceMiniBar({
    required this.displayData,
    required this.onTap,
    required this.onDisconnect,
  });

  final _DeviceMiniBarDisplayData displayData;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = displayData.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      height: 64,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _DeviceMiniBarIcon(displayData: displayData, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DeviceMiniBarText(displayData: displayData),
                    ),
                    _DeviceMiniBarTrailingAction(
                      displayData: displayData,
                      onDisconnect: onDisconnect,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceMiniBarIcon extends StatelessWidget {
  const _DeviceMiniBarIcon({required this.displayData, required this.size});

  final _DeviceMiniBarDisplayData displayData;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (displayData.deviceCount > 1) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.hub_rounded,
          color: displayData.colorScheme.primary,
          size: size - 4,
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: displayData.isConnected && displayData.deviceSvg != null
          ? SvgPicture.asset(
              displayData.deviceSvg!,
              colorFilter: ColorFilter.mode(
                displayData.colorScheme.primary,
                BlendMode.srcIn,
              ),
            )
          : Icon(
              displayData.isConnected ? Icons.usb : Icons.usb_off,
              color: displayData.isConnected
                  ? displayData.colorScheme.primary
                  : displayData.colorScheme.outline,
              size: size - 4,
            ),
    );
  }
}

class _DeviceMiniBarText extends StatelessWidget {
  const _DeviceMiniBarText({required this.displayData});

  final _DeviceMiniBarDisplayData displayData;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayData.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: displayData.isConnected
                ? displayData.colorScheme.onSurface
                : displayData.colorScheme.outline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          displayData.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: displayData.isConnected
                ? displayData.colorScheme.onSurfaceVariant
                : displayData.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _DeviceMiniBarTrailingAction extends StatelessWidget {
  const _DeviceMiniBarTrailingAction({
    required this.displayData,
    required this.onDisconnect,
  });

  final _DeviceMiniBarDisplayData displayData;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (displayData.isConnected) {
      return IconButton(
        icon: const Icon(Icons.link_off),
        onPressed: onDisconnect,
        color: displayData.colorScheme.error,
        iconSize: 20,
      );
    }

    return Icon(
      Icons.arrow_upward,
      size: 20,
      color: displayData.colorScheme.outline,
    );
  }
}

class _DeviceSheetContent extends StatelessWidget {
  const _DeviceSheetContent({
    required this.state,
    required this.scrollController,
  });

  final HardwareDeviceState state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final activeDevice = state.activeDevice;
    final isConnected = state.devices.isNotEmpty && activeDevice != null;

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const _DeviceSheetHandle(),
          if (isConnected)
            DeviceSwitcherBar(
              devices: state.devices,
              activeDeviceId: state.activeDeviceId,
            ),
          Expanded(
            child: isConnected
                ? DeviceDashboard(
                    device: activeDevice,
                    scrollController: scrollController,
                  )
                : DisconnectedState(scrollController: scrollController),
          ),
        ],
      ),
    );
  }
}

class _DeviceSheetHandle extends StatelessWidget {
  const _DeviceSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: context.colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _CompactDeviceMiniBar extends StatelessWidget {
  final bool isConnected;
  final int deviceCount;
  final String? deviceSvg;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CompactDeviceMiniBar({
    required this.isConnected,
    required this.deviceCount,
    required this.deviceSvg,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (deviceCount > 1)
                Icon(
                  Icons.hub_rounded,
                  color: colorScheme.primary,
                  size: 26,
                )
              else if (isConnected && deviceSvg != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SvgPicture.asset(
                    deviceSvg!,
                    colorFilter: ColorFilter.mode(
                      colorScheme.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                )
              else
                Icon(
                  isConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
                  color: isConnected
                      ? colorScheme.primary
                      : colorScheme.outline,
                  size: 26,
                ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? colorScheme.primary
                        : colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailExpandedDeviceMiniBar extends StatelessWidget {
  final bool isConnected;
  final int deviceCount;
  final String? deviceSvg;
  final ColorScheme colorScheme;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RailExpandedDeviceMiniBar({
    required this.isConnected,
    required this.deviceCount,
    required this.deviceSvg,
    required this.colorScheme,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: deviceCount > 1
                      ? Icon(
                          Icons.hub_rounded,
                          color: colorScheme.primary,
                          size: 24,
                        )
                      : isConnected && deviceSvg != null
                      ? SvgPicture.asset(
                          deviceSvg!,
                          colorFilter: ColorFilter.mode(
                            colorScheme.primary,
                            BlendMode.srcIn,
                          ),
                        )
                      : Icon(
                          isConnected
                              ? Icons.usb_rounded
                              : Icons.usb_off_rounded,
                          color: isConnected
                              ? colorScheme.primary
                              : colorScheme.outline,
                          size: 24,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isConnected
                        ? colorScheme.onSurface
                        : colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: isConnected
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.outline,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
