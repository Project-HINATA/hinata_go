import 'dart:async';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:neo_web_hid/neo_web_hid.dart' as neo;

import 'hid_bridge_interface.dart';

// Re-export interface for convenience
export 'hid_bridge_interface.dart';

HIDManager createHID() => WebHID();

class WebHIDDevice extends HIDDevice {
  final neo.HIDDevice _device;
  WebHIDDevice(this._device);

  @override
  int get productId => _device.productId;
  @override
  int get vendorId => _device.vendorId;
  @override
  String get productName => _device.productName;
  @override
  bool get opened => _device.opened;
  @override
  List<HIDCollectionInfo> get collections =>
      List.filled(3, HIDCollectionInfo());

  @override
  Future<void> open() => _device.open();
  @override
  Future<void> close() => _device.close();
  @override
  Future<void> sendReport(int reportId, ByteData data) =>
      _device.sendReport(reportId, data);
  @override
  void onInputReport(Function(HIDInputReportEvent)? callback) {
    if (callback == null) {
      _device.onInputReport(null);
    } else {
      _device.onInputReport((neo.HIDInputReportEvent event) {
        callback(HIDInputReportEvent(event.reportId, event.data));
      });
    }
  }
}

class WebHID extends HIDManager {
  @override
  void onConnect(Function(HIDConnectionEvent) callback) {
    neo.hid.onConnect((neo.HIDConnectionEvent event) {
      callback(HIDConnectionEvent(WebHIDDevice(event.device)));
    });
  }

  @override
  void onDisconnect(Function(HIDConnectionEvent) callback) {
    neo.hid.onDisconnect((neo.HIDConnectionEvent event) {
      callback(HIDConnectionEvent(WebHIDDevice(event.device)));
    });
  }

  @override
  bool canUseHid() => neo.canUseHid();

  @override
  Future<List<HIDDevice>> getDevices() async {
    final list = await neo.hid.getDevices();
    return list.map((d) => WebHIDDevice(d)).toList();
  }

  @override
  Future<List<HIDDevice>> requestDevice(HIDDeviceRequestOptions options) async {
    final list = await neo.hid.requestDevice(
      neo.HIDDeviceRequestOptions(
        filters: options.filters
            .map((f) => neo.RequestOptionsFilter(vendorId: f.vendorId))
            .toList(),
      ),
    );
    return list.map((d) => WebHIDDevice(d)).toList();
  }

  @override
  bool get hasFocus => web.window.document.hasFocus();
}
