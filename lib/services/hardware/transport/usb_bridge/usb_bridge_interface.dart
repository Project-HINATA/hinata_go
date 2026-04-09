import 'dart:typed_data';

class USBDeviceFilter {
  final int vendorId;
  final int productId;
  USBDeviceFilter({required this.vendorId, required this.productId});
}

class USBInTransferResult {
  final ByteData? data;
  USBInTransferResult(this.data);
}

class USBConfiguration {
  final List<USBInterface> interfaces;
  USBConfiguration(this.interfaces);
}

class USBInterface {
  final int interfaceNumber;
  final List<USBAlternateInterface> alternates;
  USBInterface(this.interfaceNumber, this.alternates);
}

class USBAlternateInterface {
  final int interfaceClass;
  final List<USBEndpoint> endpoints;
  USBAlternateInterface(this.interfaceClass, this.endpoints);
}

class USBEndpoint {
  final int endpointNumber;
  final String direction; // "in" or "out"
  USBEndpoint(this.endpointNumber, this.direction);
}

abstract class USBDevice {
  int get vendorId;
  int get productId;
  USBConfiguration? get configuration;

  Future<void> open();
  Future<void> close();
  Future<void> selectConfiguration(int number);
  Future<void> claimInterface(int number);
  Future<USBInTransferResult> transferIn(int endpointNumber, int length);
  Future<void> transferOut(int endpointNumber, Uint8List data);
}

abstract class USBManager {
  Future<USBDevice> requestDevice(List<USBDeviceFilter> filters);
}
