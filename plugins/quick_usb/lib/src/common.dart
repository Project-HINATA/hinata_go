// ignore_for_file: constant_identifier_names

class UsbDevice {
  final String identifier;
  final int vendorId;
  final int productId;
  final int configurationCount;

  UsbDevice({
    required this.identifier,
    required this.vendorId,
    required this.productId,
    required this.configurationCount,
  });

  factory UsbDevice.fromMap(Map<dynamic, dynamic> map) {
    return UsbDevice(
      identifier: map['identifier'],
      vendorId: map['vendorId'],
      productId: map['productId'],
      configurationCount: map['configurationCount'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'vendorId': vendorId,
      'productId': productId,
      'configurationCount': configurationCount,
    };
  }

  @override
  String toString() => toMap().toString();
}

enum UsbConnectionEventType { attached, detached }

class UsbConnectionEvent {
  final UsbDevice device;
  final UsbConnectionEventType type;

  UsbConnectionEvent({
    required this.device,
    required this.type,
  });

  factory UsbConnectionEvent.fromMap(Map<dynamic, dynamic> map) {
    final dynamic rawType = map['type'];
    final UsbConnectionEventType type;
    if (rawType == 'attached') {
      type = UsbConnectionEventType.attached;
    } else if (rawType == 'detached') {
      type = UsbConnectionEventType.detached;
    } else {
      throw ArgumentError.value(rawType, 'type', 'Unknown event type');
    }

    return UsbConnectionEvent(
      device: UsbDevice.fromMap(map['device'] as Map<dynamic, dynamic>),
      type: type,
    );
  }

  Map<String, dynamic> toMap() {
    final String typeName =
        type == UsbConnectionEventType.attached ? 'attached' : 'detached';

    return {
      'device': device.toMap(),
      'type': typeName,
    };
  }

  @override
  String toString() => toMap().toString();
}

class UsbConfiguration {
  final int id;
  final int index;
  final List<UsbInterface> interfaces;

  UsbConfiguration({
    required this.id,
    required this.index,
    required this.interfaces,
  });

  factory UsbConfiguration.fromMap(Map<dynamic, dynamic> map) {
    var interfaces = (map['interfaces'] as List)
        .map((e) => UsbInterface.fromMap(e))
        .toList();
    return UsbConfiguration(
      id: map['id'],
      index: map['index'],
      interfaces: interfaces,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'index': index,
      'interfaces': interfaces.map((e) => e.toMap()).toList(),
    };
  }

  @override
  String toString() => toMap().toString();
}

class UsbInterface {
  final int id;
  final int alternateSetting;
  final int interfaceClass;
  final int interfaceSubclass;
  final int interfaceProtocol;
  final List<UsbEndpoint> endpoints;

  UsbInterface({
    required this.id,
    required this.alternateSetting,
    required this.interfaceClass,
    required this.interfaceSubclass,
    required this.interfaceProtocol,
    required this.endpoints,
  });

  factory UsbInterface.fromMap(Map<dynamic, dynamic> map) {
    var endpoints =
        (map['endpoints'] as List).map((e) => UsbEndpoint.fromMap(e)).toList();
    return UsbInterface(
      id: map['id'],
      alternateSetting: map['alternateSetting'] ?? 0,
      interfaceClass: map['interfaceClass'] ?? 0,
      interfaceSubclass: map['interfaceSubclass'] ?? 0,
      interfaceProtocol: map['interfaceProtocol'] ?? 0,
      endpoints: endpoints,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alternateSetting': alternateSetting,
      'interfaceClass': interfaceClass,
      'interfaceSubclass': interfaceSubclass,
      'interfaceProtocol': interfaceProtocol,
      'endpoints': endpoints.map((e) => e.toMap()).toList(),
    };
  }

  @override
  String toString() => toMap().toString();
}

class UsbEndpoint {
  // Bits 0:3 are the endpoint number
  static const int MASK_NUMBER = 0x07;

  // Bits 4:6 are reserved

  // Bit 7 indicates direction
  static const int MASK_DIRECTION = 0x80;

  static const int DIRECTION_OUT = 0x00;
  static const int DIRECTION_IN = 0x80;

  final int endpointNumber;
  final int direction;
  final int type;
  final int maxPacketSize;

  UsbEndpoint({
    required this.endpointNumber,
    required this.direction,
    required this.type,
    required this.maxPacketSize,
  });

  factory UsbEndpoint.fromMap(Map<dynamic, dynamic> map) {
    return UsbEndpoint(
      endpointNumber: map['endpointNumber'],
      direction: map['direction'],
      type: map['type'] ?? 0,
      maxPacketSize: map['maxPacketSize'] ?? 0,
    );
  }

  int get endpointAddress => endpointNumber | direction;

  Map<String, dynamic> toMap() {
    return {
      'endpointNumber': endpointNumber,
      'direction': direction,
      'type': type,
      'maxPacketSize': maxPacketSize,
    };
  }

  @override
  String toString() => toMap().toString();
}

class UsbDeviceDescription {
  final UsbDevice device;
  final String? manufacturer;
  final String? product;
  final String? serialNumber;

  UsbDeviceDescription({
    required this.device,
    this.manufacturer,
    this.product,
    this.serialNumber,
  });

  factory UsbDeviceDescription.fromMap(Map<dynamic, dynamic> map) {
    return UsbDeviceDescription(
      device: UsbDevice.fromMap(map['device']),
      manufacturer: map['manufacturer'],
      product: map['product'],
      serialNumber: map['serialNumber'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device': device.toMap(),
      'manufacturer': manufacturer,
      'product': product,
      'serialNumber': serialNumber,
    };
  }

  @override
  String toString() => toMap().toString();
}
