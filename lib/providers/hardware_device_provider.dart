import 'dart:async';
import 'dart:developer';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../services/communication/device_interface.dart';
import '../services/communication/usb_hinata_impl.dart';
import '../services/hardware/core/hinata_device.dart';
import '../services/hardware/transport/hid_bridge/hid_bridge.dart';
import 'current_scan_session_provider.dart';
import 'nfc_provider.dart';
import 'firmware_provider.dart';

class HardwareDeviceState {
  final DeviceInterface? connectedDevice;
  final bool hidAvailable;
  final bool isConnecting;
  final String? error;
  final String? firmwareVersion;
  final int? productId;
  final bool isUpdating;

  HardwareDeviceState({
    this.connectedDevice,
    this.hidAvailable = false,
    this.isConnecting = false,
    this.error,
    this.firmwareVersion,
    this.productId,
    this.isUpdating = false,
  });

  HardwareDeviceState copyWith({
    DeviceInterface? connectedDevice,
    bool? hidAvailable,
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
      hidAvailable: hidAvailable ?? this.hidAvailable,
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
  static const _hidReadyCheckInterval = Duration(milliseconds: 50);
  static const _hidReadyMaxAttempts = 60;

  int _connectGeneration = 0;

  @override
  HardwareDeviceState build() {
    final hidAvailable = _safeCanUseHid();
    _initHidListeners();
    return HardwareDeviceState(hidAvailable: hidAvailable);
  }

  void _initHidListeners() {
    final canUseHid = _safeCanUseHid();
    if (!canUseHid) {
      log('HID unavailable on current platform/browser, skipping HID init.');
      return;
    }

    hid.onConnect((event) {
      log("Auto-connected to device: ${event.device}");
      unawaited(_connectToHidDeviceWhenReady(event.device));
    });

    hid.onDisconnect((event) {
      log("Disconnected from device: ${event.device}");
      _connectGeneration++;

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
    hid
        .getDevices()
        .then((devices) async {
          if (devices.isNotEmpty) {
            await _connectToHidDeviceWhenReady(devices.first);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          log(
            'Failed to enumerate HID devices during init.',
            error: error,
            stackTrace: stackTrace,
          );
        });
  }

  Future<void> requestUsbDevice() async {
    state = state.copyWith(isConnecting: true, error: null);
    if (!_safeCanUseHid()) {
      state = state.copyWith(
        isConnecting: false,
        error: 'USB HID is not available in this browser',
      );
      return;
    }

    try {
      final requestOptions = HIDDeviceRequestOptions(
        filters: [RequestOptionsFilter(vendorId: bridgeVendorId)],
      );
      final devices = await hid.requestDevice(requestOptions);
      if (devices.isNotEmpty) {
        await _connectToHidDeviceWhenReady(devices.first);
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

  Future<void> _connectToHidDeviceWhenReady(HIDDevice device) async {
    final generation = ++_connectGeneration;
    state = state.copyWith(isConnecting: true, error: null);

    for (var attempt = 0; attempt < _hidReadyMaxAttempts; attempt++) {
      if (generation != _connectGeneration) {
        return;
      }

      if (_isHidDeviceReady(device)) {
        await _connectToHidDevice(device, generation: generation);
        return;
      }

      await Future.delayed(_hidReadyCheckInterval);
    }

    if (generation == _connectGeneration) {
      state = state.copyWith(
        isConnecting: false,
        error: 'HID device is not ready. Please reconnect the reader.',
      );
    }
  }

  bool _isHidDeviceReady(HIDDevice device) {
    try {
      return device.collections.length > 2;
    } catch (e, s) {
      log('Failed to inspect HID device collections.', error: e, stackTrace: s);
      return false;
    }
  }

  Future<void> _connectToHidDevice(
    HIDDevice device, {
    required int generation,
  }) async {
    state = state.copyWith(isConnecting: true, error: null);
    try {
      final hinata = HINATA(device);
      final usbImpl = UsbHinataDeviceImpl(hinata);
      await usbImpl.connect();

      if (generation != _connectGeneration) {
        await usbImpl.disconnect();
        return;
      }

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
    } catch (e, s) {
      if (generation != _connectGeneration) {
        return;
      }
      log('Failed to connect HID device.', error: e, stackTrace: s);
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
        final scannedCard = await usbImpl.poll();

        if (scannedCard != null) {
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
    _connectGeneration++;
    await state.connectedDevice?.disconnect();
    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: 'HINATA');
    state = state.copyWith(clearDevice: true);
  }

  bool _safeCanUseHid() {
    try {
      return hid.canUseHid();
    } catch (e, s) {
      log('Failed to probe HID availability.', error: e, stackTrace: s);
      return false;
    }
  }
}

final hardwareDeviceProvider =
    NotifierProvider<HardwareDeviceNotifier, HardwareDeviceState>(() {
      return HardwareDeviceNotifier();
    });
