import 'dart:async';
import 'dart:typed_data';
import 'package:quick_usb/quick_usb.dart' as native;
import 'usb_bridge_interface.dart';

// Re-export interface for convenience
export 'usb_bridge_interface.dart';

USBManager createUSB() => NativeUSB();

class NativeUSBDevice extends USBDevice {
  final native.UsbDevice _usbDevice;
  bool _opened = false;
  USBConfiguration? _configuration;

  NativeUSBDevice(this._usbDevice);

  @override
  int get vendorId => _usbDevice.vendorId;
  @override
  int get productId => _usbDevice.productId;
  @override
  USBConfiguration? get configuration => _configuration;

  @override
  Future<void> open() async {
    if (_opened) return;
    await native.QuickUsb.init();
    if (!await native.QuickUsb.hasPermission(_usbDevice)) {
      await native.QuickUsb.requestPermission(_usbDevice);
    }
    _opened = await native.QuickUsb.openDevice(_usbDevice);
  }

  @override
  Future<void> close() async {
    _opened = false;
    await native.QuickUsb.closeDevice();
  }

  @override
  Future<void> selectConfiguration(int number) async {
    final config = await native.QuickUsb.getConfiguration(number - 1);
    _configuration = USBConfiguration(
      config.interfaces.map((itf) {
        return USBInterface(itf.id, [
          USBAlternateInterface(
            itf.interfaceClass,
            itf.endpoints.map((ep) {
              return USBEndpoint(
                ep.endpointNumber,
                ep.direction == 0x80 ? "in" : "out",
              );
            }).toList(),
          ),
        ]);
      }).toList(),
    );
  }

  @override
  Future<void> claimInterface(int number) async {
    if (_configuration == null) await selectConfiguration(1);
    final config = await native.QuickUsb.getConfiguration(0);
    final itf = config.interfaces.firstWhere((i) => i.id == number);
    await native.QuickUsb.claimInterface(itf);
  }

  @override
  Future<USBInTransferResult> transferIn(int endpointNumber, int length) async {
    final ep = native.UsbEndpoint(
      endpointNumber: endpointNumber,
      direction: 0x80,
      type: 0x02,
      maxPacketSize: 64,
    );
    final data = await native.QuickUsb.bulkTransferIn(ep, length);
    return USBInTransferResult(ByteData.sublistView(data));
  }

  @override
  Future<void> transferOut(int endpointNumber, Uint8List data) async {
    final ep = native.UsbEndpoint(
      endpointNumber: endpointNumber,
      direction: 0x00,
      type: 0x02,
      maxPacketSize: 64,
    );
    await native.QuickUsb.bulkTransferOut(ep, data);
  }
}

class NativeUSB extends USBManager {
  @override
  Future<USBDevice> requestDevice(List<USBDeviceFilter> filters) async {
    await native.QuickUsb.init();
    final list = await native.QuickUsb.getDeviceList();
    final match = list.firstWhere(
      (d) => filters.any(
        (f) => d.vendorId == f.vendorId && d.productId == f.productId,
      ),
    );
    return NativeUSBDevice(match);
  }
}
