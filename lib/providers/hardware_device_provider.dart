import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/card/card_read_result.dart';
import '../models/card/scanned_card.dart';
import '../models/card/transit.dart';
import '../services/communication/device_interface.dart';
import '../services/communication/remote_hinata_impl.dart';
import '../services/communication/usb_hinata_impl.dart';
import 'current_scan_session_provider.dart';
import 'firmware_provider.dart';
import 'nfc_provider.dart';

class HardwareDeviceState {
  final Map<String, DeviceInterface> devices;
  final String? activeDeviceId;
  final Map<String, String> deviceAliases;
  final bool hidAvailable;
  final bool isConnecting;
  final String? error;
  final String? _firmwareVersion;
  final int? _productId;
  final bool isUpdating;

  HardwareDeviceState({
    Map<String, DeviceInterface>? devices,
    String? activeDeviceId,
    Map<String, String>? deviceAliases,
    DeviceInterface? connectedDevice,
    this.hidAvailable = false,
    this.isConnecting = false,
    this.error,
    String? firmwareVersion,
    int? productId,
    this.isUpdating = false,
  })  : devices = devices ??
            (connectedDevice != null
                ? {connectedDevice.deviceId: connectedDevice}
                : const {}),
        activeDeviceId = activeDeviceId ?? connectedDevice?.deviceId,
        deviceAliases = deviceAliases ?? const {},
        _firmwareVersion = firmwareVersion,
        _productId = productId;

  DeviceInterface? get activeDevice =>
      activeDeviceId != null ? devices[activeDeviceId] : devices.values.firstOrNull;

  DeviceInterface? get connectedDevice => activeDevice;

  String? get firmwareVersion {
    final dev = activeDevice;
    if (dev is UsbHinataDeviceImpl) {
      try {
        return dev.firmVersion;
      } catch (_) {}
    }
    return _firmwareVersion;
  }

  int? get productId {
    final dev = activeDevice;
    if (dev is UsbHinataDeviceImpl) {
      try {
        return dev.productId;
      } catch (_) {}
    }
    return _productId;
  }

  HardwareDeviceState copyWith({
    Map<String, DeviceInterface>? devices,
    String? activeDeviceId,
    bool clearActiveDevice = false,
    Map<String, String>? deviceAliases,
    DeviceInterface? connectedDevice,
    bool? hidAvailable,
    bool? isConnecting,
    String? error,
    bool clearError = false,
    String? firmwareVersion,
    int? productId,
    bool? isUpdating,
    bool clearDevice = false,
  }) {
    if (clearDevice) {
      return HardwareDeviceState(
        devices: const {},
        activeDeviceId: null,
        deviceAliases: deviceAliases ?? this.deviceAliases,
        hidAvailable: hidAvailable ?? this.hidAvailable,
        isConnecting: isConnecting ?? false,
        error: clearError ? null : (error ?? this.error),
        firmwareVersion: null,
        productId: null,
        isUpdating: isUpdating ?? this.isUpdating,
      );
    }

    Map<String, DeviceInterface> newDevices;
    if (devices != null) {
      newDevices = devices;
    } else if (connectedDevice != null) {
      newDevices = {connectedDevice.deviceId: connectedDevice};
    } else {
      newDevices = this.devices;
    }

    String? newActiveDeviceId;
    if (clearActiveDevice) {
      newActiveDeviceId = null;
    } else if (activeDeviceId != null) {
      newActiveDeviceId = activeDeviceId;
    } else if (connectedDevice != null) {
      newActiveDeviceId = connectedDevice.deviceId;
    } else if (this.activeDeviceId != null &&
        newDevices.containsKey(this.activeDeviceId)) {
      newActiveDeviceId = this.activeDeviceId;
    } else {
      newActiveDeviceId = newDevices.keys.firstOrNull;
    }

    return HardwareDeviceState(
      devices: newDevices,
      activeDeviceId: newActiveDeviceId,
      deviceAliases: deviceAliases ?? this.deviceAliases,
      hidAvailable: hidAvailable ?? this.hidAvailable,
      isConnecting: isConnecting ?? this.isConnecting,
      error: clearError ? null : (error ?? this.error),
      firmwareVersion: firmwareVersion ?? _firmwareVersion,
      productId: productId ?? _productId,
      isUpdating: isUpdating ?? this.isUpdating,
    );
  }
}

typedef DeviceRegistryState = HardwareDeviceState;

class HardwareDeviceNotifier extends Notifier<HardwareDeviceState> {
  static const _hidReadyCheckInterval = Duration(milliseconds: 50);
  static const _hidReadyMaxAttempts = 60;
  static const _pollInterval = Duration(milliseconds: 16);

  int _connectGeneration = 0;
  final Set<String> _connectingDeviceKeys = {};

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
      _handleHidDisconnect(event.device);
    });

    // Try to get already connected devices
    hid
        .getDevices()
        .then((devices) async {
          for (final dev in devices) {
            unawaited(_connectToHidDeviceWhenReady(dev));
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
    state = state.copyWith(isConnecting: true, clearError: true);
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
        for (final dev in devices) {
          unawaited(_connectToHidDeviceWhenReady(dev));
        }
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
    final deviceKey = _hidDeviceKey(device);
    if (_connectingDeviceKeys.contains(deviceKey)) {
      return;
    }
    if (_isConnectedToHidDevice(device)) {
      return;
    }

    _connectingDeviceKeys.add(deviceKey);
    final generation = ++_connectGeneration;
    state = state.copyWith(isConnecting: true, clearError: true);

    try {
      for (var attempt = 0; attempt < _hidReadyMaxAttempts; attempt++) {
        if (generation != _connectGeneration && !state.isConnecting) {
          // superseded
        }

        if (_isHidDeviceReady(device)) {
          await _connectToHidDevice(device, deviceKey: deviceKey);
          return;
        }

        await Future.delayed(_hidReadyCheckInterval);
      }

      state = state.copyWith(
        isConnecting: false,
        error: 'HID device is not ready. Please reconnect the reader.',
      );
    } finally {
      _connectingDeviceKeys.remove(deviceKey);
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
    required String deviceKey,
  }) async {
    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      final hinata = HinataReader(device);
      final deviceId = _usbDeviceId(device);
      final alias = state.deviceAliases[deviceId];
      final usbImpl = UsbHinataDeviceImpl(
        hinata,
        deviceId: deviceId,
        alias: alias,
      );
      await usbImpl.connect();

      final firmVer = hinata.firmVersion;
      final pid = device.productId;

      final updatedDevices = Map<String, DeviceInterface>.from(state.devices);
      updatedDevices[deviceId] = usbImpl;

      final newActiveId = state.activeDeviceId ?? deviceId;

      state = state.copyWith(
        devices: updatedDevices,
        activeDeviceId: newActiveId,
        isConnecting: false,
        firmwareVersion: firmVer,
        productId: pid,
      );

      if (firmwareFeatureEnabled && state.activeDeviceId == deviceId) {
        unawaited(ref.read(firmwareProvider.notifier).requestFirmware(usbImpl));
      }

      usbImpl.connectionState.addListener(() {
        if (usbImpl.connectionState.value == DeviceConnectionState.disconnected) {
          final isUpdating = ref.read(firmwareProvider).isUpdating;
          if (!isUpdating && state.devices.containsKey(deviceId)) {
            _removeDevice(deviceId, usbImpl);
          }
        }
      });

      _startPollLoop(usbImpl);
    } catch (e, s) {
      log('Failed to connect HID device.', error: e, stackTrace: s);
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  void _handleHidDisconnect(HIDDevice device) {
    _connectGeneration++;
    if (state.isUpdating) {
      log("Ignoring disconnect during update mode.");
      return;
    }

    final targetKey = _usbDeviceId(device);
    DeviceInterface? matchedDevice;
    String? matchedId;

    for (final entry in state.devices.entries) {
      if (entry.key == targetKey) {
        matchedId = entry.key;
        matchedDevice = entry.value;
        break;
      }
      if (entry.value is UsbHinataDeviceImpl) {
        final usb = entry.value as UsbHinataDeviceImpl;
        if (usb.deviceId == targetKey || usb.deviceId == device.productId.toString()) {
          matchedId = entry.key;
          matchedDevice = entry.value;
          break;
        }
      }
    }

    if (matchedId != null && matchedDevice != null) {
      _removeDevice(matchedId, matchedDevice);
    }
  }

  void registerDevice(DeviceInterface device) {
    final deviceId = device.deviceId;
    if (state.deviceAliases.containsKey(deviceId)) {
      if (device is UsbHinataDeviceImpl) {
        device.alias = state.deviceAliases[deviceId];
      }
    }

    final updatedDevices = Map<String, DeviceInterface>.from(state.devices);
    updatedDevices[deviceId] = device;

    final newActiveId = state.activeDeviceId ?? deviceId;

    state = state.copyWith(
      devices: updatedDevices,
      activeDeviceId: newActiveId,
      isConnecting: false,
    );

    device.connectionState.addListener(() {
      if (device.connectionState.value == DeviceConnectionState.disconnected) {
        final isUpdating = ref.read(firmwareProvider).isUpdating;
        if (!isUpdating && state.devices.containsKey(deviceId)) {
          _removeDevice(deviceId, device);
        }
      }
    });

    if (device is UsbHinataDeviceImpl) {
      _startPollLoop(device);
    }
  }

  void registerRemoteDevice(RemoteHinataDeviceImpl device) {
    registerDevice(device);
  }

  void unregisterRemoteDevice(String deviceId) {
    final device = state.devices[deviceId];
    if (device != null) {
      _removeDevice(deviceId, device);
    }
  }

  void selectDevice(String deviceId) {
    if (!state.devices.containsKey(deviceId)) return;

    state = state.copyWith(activeDeviceId: deviceId);
    final dev = state.devices[deviceId];
    if (firmwareFeatureEnabled && dev is UsbHinataDeviceImpl) {
      unawaited(ref.read(firmwareProvider.notifier).requestFirmware(dev));
    }
  }

  void setDeviceAlias(String deviceId, String alias) {
    final updatedAliases = Map<String, String>.from(state.deviceAliases);
    final trimmed = alias.trim();
    if (trimmed.isEmpty) {
      updatedAliases.remove(deviceId);
    } else {
      updatedAliases[deviceId] = trimmed;
    }

    final dev = state.devices[deviceId];
    if (dev != null) {
      try {
        (dev as dynamic).alias = trimmed.isEmpty ? null : trimmed;
      } catch (_) {}
    }

    state = state.copyWith(deviceAliases: updatedAliases);
  }

  void disconnect([String? deviceId]) {
    if (deviceId != null) {
      final dev = state.devices[deviceId];
      if (dev != null) {
        _removeDevice(deviceId, dev);
      }
      return;
    }

    final active = state.activeDevice;
    if (active != null) {
      final id = state.activeDeviceId ??
          state.devices.entries.firstWhere((e) => e.value == active).key;
      _removeDevice(id, active);
    } else {
      disconnectAll();
    }
  }

  void disconnectAll() {
    _connectGeneration++;
    _connectingDeviceKeys.clear();
    for (final entry in state.devices.entries) {
      unawaited(entry.value.disconnect());
      ref.read(currentScanSessionProvider.notifier).markCardRemoved(
        source: entry.value.displayTitle.isNotEmpty
            ? entry.value.displayTitle
            : 'HINATA',
      );
    }
    state = state.copyWith(clearDevice: true);
  }

  void _removeDevice(String deviceId, DeviceInterface device) {
    if (!state.devices.containsKey(deviceId)) return;

    final updatedDevices = Map<String, DeviceInterface>.from(state.devices)
      ..remove(deviceId);
    final newActiveId = state.activeDeviceId == deviceId
        ? updatedDevices.keys.firstOrNull
        : state.activeDeviceId;

    unawaited(device.disconnect());
    ref.read(currentScanSessionProvider.notifier).markCardRemoved(
      source: device.displayTitle.isNotEmpty ? device.displayTitle : 'HINATA',
    );

    state = state.copyWith(
      devices: updatedDevices,
      activeDeviceId: newActiveId,
      clearActiveDevice: newActiveId == null,
      clearDevice: updatedDevices.isEmpty,
    );
  }

  Future<void> _startPollLoop(UsbHinataDeviceImpl usbImpl) async {
    final deviceId = usbImpl.deviceId;

    while (state.devices.containsKey(deviceId) &&
        usbImpl.connectionState.value == DeviceConnectionState.connected) {
      final source =
          usbImpl.displayTitle.isNotEmpty ? usbImpl.displayTitle : 'HINATA';

      if (!hid.hasFocus) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        // 1. Phase 1: Fast poll for basic info
        final pollResult = await usbImpl.pollResult(readExtended: false);
        final rawScannedCard = pollResult.card;

        if (rawScannedCard != null) {
          final scannedCard = rawScannedCard.source == source
              ? rawScannedCard
              : ScannedCard(
                  card: rawScannedCard.card,
                  source: source,
                  timestamp: rawScannedCard.timestamp,
                  isExtendedInfoFullyLoaded:
                      rawScannedCard.isExtendedInfoFullyLoaded,
                  isUsable: rawScannedCard.isUsable,
                );

          debugPrint(
            '[_startPollLoop:$deviceId] Fast poll returned card: ${scannedCard.card.idString}, type: ${scannedCard.card.runtimeType}',
          );

          final recordResult = await ref
              .read(nfcProvider.notifier)
              .handleExternalScan(
                scannedCard,
                presenceMode: ScanPresenceMode.explicitRemoval,
              );
          debugPrint('[_startPollLoop:$deviceId] recordScan result: $recordResult');

          // 2. If it is a transit card, read extended info sequentially if not yet loaded
          final sessionState = ref.read(currentScanSessionProvider);
          if (scannedCard.card is TransitCard &&
              !sessionState.isReadingExtendedInfo &&
              !sessionState.isExtendedInfoLoaded) {
            ref
                .read(currentScanSessionProvider.notifier)
                .setReadingExtendedInfo(true);

            // Yield to Flutter to paint Phase 1 UI immediately
            await Future.delayed(const Duration(milliseconds: 50));

            try {
              debugPrint(
                '[_startPollLoop:$deviceId] Starting Phase 2 sequential read...',
              );
              final extendedCard = await usbImpl.readExtended(
                sessionState.scannedCard ?? scannedCard,
              );
              if (extendedCard != null) {
                final finalExtended = extendedCard.source == source
                    ? extendedCard
                    : ScannedCard(
                        card: extendedCard.card,
                        source: source,
                        timestamp: extendedCard.timestamp,
                        isExtendedInfoFullyLoaded:
                            extendedCard.isExtendedInfoFullyLoaded,
                        isUsable: extendedCard.isUsable,
                      );
                final extendedTransitCard = finalExtended.card;
                if (extendedTransitCard is TransitCard) {
                  ref
                      .read(currentScanSessionProvider.notifier)
                      .updateCard(finalExtended);
                  await ref
                      .read(nfcProvider.notifier)
                      .updateExternalScan(finalExtended);
                }
              }
            } catch (e) {
              debugPrint(
                '[_startPollLoop:$deviceId] Error reading extended transit history via USB: $e',
              );
            } finally {
              ref
                  .read(currentScanSessionProvider.notifier)
                  .setReadingExtendedInfo(false);
            }
          }
        } else if (pollResult.status == CardReadStatus.noTarget) {
          final cardRemoved = ref
              .read(currentScanSessionProvider.notifier)
              .markCardMissing(source: source);
          if (cardRemoved) {
            debugPrint(
              '[_startPollLoop:$deviceId] Marked $source card removed after transient poll misses',
            );
          }
        }
      } catch (e) {
        log("Polling error ($deviceId): $e");
      }

      await Future.delayed(_pollInterval);
    }

    final finalSource =
        usbImpl.displayTitle.isNotEmpty ? usbImpl.displayTitle : 'HINATA';
    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: finalSource);
  }

  void setIsUpdating(bool updating) {
    state = state.copyWith(isUpdating: updating);
  }

  bool _safeCanUseHid() {
    try {
      return hid.canUseHid();
    } catch (e, s) {
      log('Failed to probe HID availability.', error: e, stackTrace: s);
      return false;
    }
  }

  String _usbDeviceId(HIDDevice device) {
    return 'usb:${device.productId}:${_hidDeviceKey(device)}';
  }

  String _hidDeviceKey(HIDDevice device) {
    return '${device.vendorId}:${device.productId}:${identityHashCode(device)}';
  }

  bool _isConnectedToHidDevice(HIDDevice device) {
    for (final dev in state.devices.values) {
      if (dev is UsbHinataDeviceImpl) {
        if (identical(dev.device, device) || dev.deviceId == _usbDeviceId(device)) {
          return true;
        }
      }
    }
    return false;
  }
}

typedef DeviceRegistryNotifier = HardwareDeviceNotifier;

final hardwareDeviceProvider =
    NotifierProvider<HardwareDeviceNotifier, HardwareDeviceState>(() {
      return HardwareDeviceNotifier();
    });

final deviceRegistryProvider = hardwareDeviceProvider;
