import 'dart:async';
import 'dart:typed_data';
import 'package:neo_web_usb/neo_web_usb.dart' as neo;
import 'usb_bridge_interface.dart';

// Re-export interface for convenience
export 'usb_bridge_interface.dart';

USBManager createUSB() => WebUSB();

class WebUSBDevice extends USBDevice {
  final neo.USBDevice _device;
  WebUSBDevice(this._device);

  @override
  int get vendorId => _device.vendorId;
  @override
  int get productId => _device.productId;

  @override
  USBConfiguration? get configuration {
    if (_device.configuration == null) return null;
    return USBConfiguration(
      _device.configuration!.interfaces.map((itf) {
        return USBInterface(
          itf.interfaceNumber,
          itf.alternates.map((alt) {
            return USBAlternateInterface(
              alt.interfaceClass,
              alt.endpoints.map((ep) {
                return USBEndpoint(ep.endpointNumber, ep.direction);
              }).toList(),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  @override
  Future<void> open() => _device.open();
  @override
  Future<void> close() => _device.close();
  @override
  Future<void> selectConfiguration(int number) =>
      _device.selectConfiguration(number);
  @override
  Future<void> claimInterface(int number) => _device.claimInterface(number);
  @override
  Future<USBInTransferResult> transferIn(int endpointNumber, int length) async {
    final result = await _device.transferIn(endpointNumber, length);
    return USBInTransferResult(result.data);
  }

  @override
  Future<void> transferOut(int endpointNumber, Uint8List data) =>
      _device.transferOut(endpointNumber, data);
}

class WebUSB extends USBManager {
  @override
  Future<USBDevice> requestDevice(List<USBDeviceFilter> filters) async {
    // The neo_web_usb package exports a top-level 'usb' instance
    final device = await neo.usb.requestDevice(
      filters
          .map(
            (f) => neo.USBDeviceFilter(
              vendorId: f.vendorId,
              productId: f.productId,
            ),
          )
          .toList(),
    );
    return WebUSBDevice(device);
  }
}
