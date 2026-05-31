import 'dart:typed_data';

class HIDDeviceRequestOptions {
  final List<RequestOptionsFilter> filters;
  HIDDeviceRequestOptions({required this.filters});
}

class RequestOptionsFilter {
  final int vendorId;
  RequestOptionsFilter({required this.vendorId});
}

class HIDConnectionEvent {
  final HIDDevice device;
  HIDConnectionEvent(this.device);

  @override
  String toString() => 'HIDConnectionEvent(device: $device)';
}

class HIDInputReportEvent {
  final int reportId;
  final ByteData data;
  HIDInputReportEvent(this.reportId, this.data);
}

// Mocking HIDCollectionInfo as expected by HINATA
class HIDCollectionInfo {}

abstract class HIDDevice {
  int get productId;
  int get vendorId;
  String get productName;
  bool get opened;
  List<HIDCollectionInfo> get collections;

  Future<void> open();
  Future<void> close();
  Future<void> sendReport(int reportId, ByteData data);
  void onInputReport(Function(HIDInputReportEvent)? callback);
}

abstract class HIDManager {
  void onConnect(Function(HIDConnectionEvent) callback);
  void onDisconnect(Function(HIDConnectionEvent) callback);
  bool canUseHid();
  Future<List<HIDDevice>> getDevices();
  Future<List<HIDDevice>> requestDevice(HIDDeviceRequestOptions options);

  /// Returns true if the app is currently focused (relevant for Web/Desktop).
  /// On Mobile, this typically returns true if the app is in foreground.
  bool get hasFocus;
}
