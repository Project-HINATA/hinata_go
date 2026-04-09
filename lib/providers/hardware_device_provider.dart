import 'dart:async';
import 'dart:developer';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../services/communication/device_interface.dart';
import '../services/communication/usb_hinata_impl.dart';
import '../services/hardware/core/hinata_device.dart';
import '../services/hardware/transport/hid_bridge/hid_bridge.dart';
import '../models/card/scanned_card.dart';
import 'current_scan_session_provider.dart';
import 'nfc_provider.dart';
import 'firmware_provider.dart';

class HardwareDeviceState {
  final DeviceInterface? connectedDevice;
  final bool isConnecting;
  final String? error;
  final String? firmwareVersion;
  final int? productId;
  final bool isUpdating;

  HardwareDeviceState({
    this.connectedDevice,
    this.isConnecting = false,
    this.error,
    this.firmwareVersion,
    this.productId,
    this.isUpdating = false,
  });

  HardwareDeviceState copyWith({
    DeviceInterface? connectedDevice,
    bool? isConnecting,
    String? error,
    String? firmwareVersion,
    int? productId,
    bool? isUpdating,
    bool clearDevice = false,
  }) {
    return HardwareDeviceState(
      connectedDevice: clearDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
      firmwareVersion: clearDevice
          ? null
          : (firmwareVersion ?? this.firmwareVersion),
      productId: clearDevice ? null : (productId ?? this.productId),
      isUpdating: isUpdating ?? this.isUpdating,
    );
  }
}

class HardwareDeviceNotifier extends Notifier<HardwareDeviceState> {
  @override
  HardwareDeviceState build() {
    _initHidListeners();
    return HardwareDeviceState();
  }

  void _initHidListeners() {
    hid.onConnect((event) {
      log("Auto-connected to device: ${event.device}");
      _connectToHidDevice(event.device);
    });

    hid.onDisconnect((event) {
      log("Disconnected from device: ${event.device}");

      // Protect state if we are currently flashing/updating
      if (state.isUpdating) {
        log("Ignoring disconnect during update mode.");
        return;
      }

      if (state.connectedDevice is UsbHinataDeviceImpl) {
        final usbDev = state.connectedDevice as UsbHinataDeviceImpl;
        if (usbDev.deviceId == event.device.productId.toString()) {
          unawaited(usbDev.disconnect());
          ref
              .read(currentScanSessionProvider.notifier)
              .markCardRemoved(source: 'HINATA');
          state = state.copyWith(clearDevice: true);
        }
      }
    });

    // Try to get already connected devices
    hid.getDevices().then((devices) {
      if (devices.isNotEmpty) {
        _connectToHidDevice(devices.first);
      }
    });
  }

  Future<void> requestUsbDevice() async {
    state = state.copyWith(isConnecting: true, error: null);
    try {
      final requestOptions = HIDDeviceRequestOptions(
        filters: [RequestOptionsFilter(vendorId: bridgeVendorId)],
      );
      final devices = await hid.requestDevice(requestOptions);
      if (devices.isNotEmpty) {
        await _connectToHidDevice(devices.first);
      } else {
        state = state.copyWith(
          isConnecting: false,
          error: 'No device selected',
        );
      }
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> _connectToHidDevice(HIDDevice device) async {
    state = state.copyWith(isConnecting: true, error: null);
    try {
      final hinata = HINATA(device);
      final usbImpl = UsbHinataDeviceImpl(hinata);
      await usbImpl.connect();

      final firmVer = hinata.firmVersion;
      final pid = device.productId;

      state = state.copyWith(
        connectedDevice: usbImpl,
        isConnecting: false,
        firmwareVersion: firmVer,
        productId: pid,
      );

      // Trigger background firmware status check immediately
      if (firmwareFeatureEnabled) {
        ref.read(firmwareProvider.notifier).requestFirmware(usbImpl);
      }

      usbImpl.connectionState.addListener(() {
        if (usbImpl.connectionState.value ==
            DeviceConnectionState.disconnected) {
          // Check if we are currently updating to prevent state clearing
          final isUpdating = ref.read(firmwareProvider).isUpdating;
          if (state.connectedDevice == usbImpl && !isUpdating) {
            state = state.copyWith(clearDevice: true);
          }
        }
      });
      _startPollLoop(usbImpl);
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> _startPollLoop(UsbHinataDeviceImpl usbImpl) async {
    while (state.connectedDevice == usbImpl) {
      if (!hid.hasFocus) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        final card = await usbImpl.poll();

        if (card != null) {
          final scannedCard = ScannedCard(card: card, source: 'HINATA');
          await ref
              .read(nfcProvider.notifier)
              .handleExternalScan(
                scannedCard,
                presenceMode: ScanPresenceMode.explicitRemoval,
              );
        } else {
          ref
              .read(currentScanSessionProvider.notifier)
              .markCardRemoved(source: 'HINATA');
        }
      } catch (e) {
        log("Polling error: $e");
        continue;
      }
    }

    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: 'HINATA');
  }

  void setIsUpdating(bool updating) {
    state = state.copyWith(isUpdating: updating);
  }

  void disconnect() async {
    await state.connectedDevice?.disconnect();
    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: 'HINATA');
    state = state.copyWith(clearDevice: true);
  }
}

final hardwareDeviceProvider =
    NotifierProvider<HardwareDeviceNotifier, HardwareDeviceState>(() {
      return HardwareDeviceNotifier();
    });
