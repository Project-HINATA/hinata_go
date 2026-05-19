import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../transport/hid_bridge/hid_bridge.dart';
import 'hinata_reader.dart';

class HinataReaderManager {
  HinataReaderManager({HIDManager? hidManager}) : _hid = hidManager ?? hid;

  static const Duration defaultReadyCheckInterval = Duration(milliseconds: 50);
  static const int defaultReadyMaxAttempts = 60;

  final HIDManager _hid;

  bool get isAvailable {
    try {
      return _hid.canUseHid();
    } catch (e, s) {
      log('Failed to probe HID availability.', error: e, stackTrace: s);
      return false;
    }
  }

  bool get hasFocus => _hid.hasFocus;

  void onConnect(ValueChanged<HIDConnectionEvent> callback) {
    if (!isAvailable) return;
    _hid.onConnect(callback);
  }

  void onDisconnect(ValueChanged<HIDConnectionEvent> callback) {
    if (!isAvailable) return;
    _hid.onDisconnect(callback);
  }

  Future<List<HinataReader>> connectedReaders() async {
    if (!isAvailable) return const [];
    final devices = await _hid.getDevices();
    return devices.map(HinataReader.new).toList(growable: false);
  }

  Future<List<HinataReader>> requestReaders() async {
    if (!isAvailable) return const [];

    final requestOptions = HIDDeviceRequestOptions(
      filters: [RequestOptionsFilter(vendorId: bridgeVendorId)],
    );
    final devices = await _hid.requestDevice(requestOptions);
    return devices.map(HinataReader.new).toList(growable: false);
  }

  Future<HinataReader?> waitUntilReady(
    HIDDevice device, {
    Duration interval = defaultReadyCheckInterval,
    int maxAttempts = defaultReadyMaxAttempts,
    bool Function()? shouldCancel,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (shouldCancel?.call() ?? false) {
        return null;
      }

      if (_isHidDeviceReady(device)) {
        return HinataReader(device);
      }

      await Future<void>.delayed(interval);
    }

    return null;
  }

  bool _isHidDeviceReady(HIDDevice device) {
    try {
      return device.collections.length > 2;
    } catch (e, s) {
      log('Failed to inspect HID device collections.', error: e, stackTrace: s);
      return false;
    }
  }
}
