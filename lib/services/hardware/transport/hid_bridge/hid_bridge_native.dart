import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:quick_usb/quick_usb.dart';
import 'hid_bridge_interface.dart';

// Re-export interface for convenience
export 'hid_bridge_interface.dart';

HIDManager createHID() => NativeHID();

const _nativeBridgeVendorId = 0xF822;

class NativeHIDDevice extends HIDDevice {
  final UsbDevice _usbDevice;
  UsbEndpoint? _readEndpoint;
  UsbEndpoint? _writeEndpoint;
  bool _opened = false;
  String _productName = "";
  Function(HIDInputReportEvent)? _inputReportHandler;
  StreamSubscription<Uint8List>? _readSubscription;

  NativeHIDDevice(this._usbDevice);

  @override
  int get productId => _usbDevice.productId;
  @override
  int get vendorId => _usbDevice.vendorId;
  @override
  String get productName => _productName;
  @override
  bool get opened => _opened;
  @override
  List<HIDCollectionInfo> get collections =>
      List.filled(3, HIDCollectionInfo());

  @override
  Future<void> open() async {
    if (_opened) return;
    try {
      await QuickUsb.init();
      if (!await QuickUsb.hasPermission(_usbDevice)) {
        await QuickUsb.requestPermission(_usbDevice);
      }

      final desc = await QuickUsb.getDeviceDescription(_usbDevice);
      _productName = desc.product ?? "";

      if (!await QuickUsb.openDevice(_usbDevice)) {
        throw Exception('Failed to open USB device');
      }

      // Probe endpoints
      for (var i = 0; i < _usbDevice.configurationCount; i++) {
        final config = await QuickUsb.getConfiguration(i);
        for (var intf in config.interfaces) {
          if (intf.interfaceClass == 2 || intf.interfaceClass == 10) continue;
          if (await QuickUsb.claimInterface(intf)) {
            for (var ep in intf.endpoints) {
              if (ep.direction == 0x80) {
                _readEndpoint = ep;
              } else if (ep.direction == 0x00) {
                _writeEndpoint = ep;
              }
            }
          }
        }
      }

      if (_readEndpoint == null || _writeEndpoint == null) {
        throw Exception('Could not find suitable endpoints');
      }

      _opened = true;
      _startReadStream();
    } catch (e) {
      log('Error opening HID device: $e');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _opened = false;
    _readSubscription?.cancel();
    _readSubscription = null;
    try {
      await QuickUsb.stopBulkTransferInStream();
      await QuickUsb.closeDevice();
    } catch (e) {
      log('Error closing device: $e');
    }
  }

  @override
  Future<void> sendReport(int reportId, ByteData data) async {
    if (!_opened || _writeEndpoint == null) return;

    final payload = data.buffer.asUint8List();
    final buffer = Uint8List(payload.length + 1);
    buffer[0] = reportId;
    buffer.setRange(1, buffer.length, payload);

    await QuickUsb.bulkTransferOut(_writeEndpoint!, buffer);
  }

  @override
  void onInputReport(Function(HIDInputReportEvent)? callback) {
    _inputReportHandler = callback;
  }

  void _startReadStream() {
    if (_readEndpoint == null) return;

    final stream = QuickUsb.bulkTransferInStream(
      _readEndpoint!,
      64,
      timeout: 50,
    );

    _readSubscription = stream.listen(
      (Uint8List data) {
        if (data.isEmpty || _inputReportHandler == null) return;
        final reportId = data[0];
        final payload = data.sublist(1);
        _inputReportHandler!(
          HIDInputReportEvent(reportId, ByteData.sublistView(payload)),
        );
      },
      onError: (error) {
        log('USB read stream error: $error');
      },
    );
  }

  @override
  String toString() => 'NativeHIDDevice(PID: ${productId.toRadixString(16)})';
}

class NativeHID extends HIDManager {
  static final List<Function(HIDConnectionEvent)> _connectCallbacks = [];
  static final List<Function(HIDConnectionEvent)> _disconnectCallbacks = [];
  static StreamSubscription<UsbConnectionEvent>? _deviceConnectionSubscription;

  NativeHID() {
    _ensureDeviceConnectionListener();
  }

  @override
  void onConnect(Function(HIDConnectionEvent) callback) {
    _connectCallbacks.add(callback);
  }

  @override
  void onDisconnect(Function(HIDConnectionEvent) callback) {
    _disconnectCallbacks.add(callback);
  }

  @override
  bool canUseHid() => true;

  @override
  Future<List<HIDDevice>> getDevices() async {
    await QuickUsb.init();
    final list = await QuickUsb.getDeviceList();
    return list
        .where((d) => d.vendorId == 0xF822)
        .map((d) => NativeHIDDevice(d))
        .toList();
  }

  @override
  Future<List<HIDDevice>> requestDevice(HIDDeviceRequestOptions options) async {
    return getDevices();
  }

  @override
  bool get hasFocus => true; // Always true for native (no web document focus concept)

  void _ensureDeviceConnectionListener() {
    _deviceConnectionSubscription ??= QuickUsb.deviceConnectionEvents.listen(
      (event) {
        if (event.device.vendorId != _nativeBridgeVendorId) {
          return;
        }

        final hidEvent = HIDConnectionEvent(NativeHIDDevice(event.device));
        final callbacks = event.type == UsbConnectionEventType.attached
            ? _connectCallbacks
            : _disconnectCallbacks;

        for (final callback in List<Function(HIDConnectionEvent)>.from(
          callbacks,
        )) {
          callback(hidEvent);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        log(
          'USB hotplug listener error: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }
}
