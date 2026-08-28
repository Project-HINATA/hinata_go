import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/services/reader/usb_hinata_impl.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

class _NoTagHidDevice implements HIDDevice {
  Function(HIDInputReportEvent)? _inputReportCallback;

  @override
  List<HIDCollectionInfo> get collections => const [];

  @override
  bool get opened => true;

  @override
  int get productId => 0;

  @override
  String get productName => 'test';

  @override
  int get vendorId => 0;

  @override
  Future<void> close() async {}

  @override
  Future<void> open() async {}

  @override
  void onInputReport(Function(HIDInputReportEvent)? callback) {
    _inputReportCallback = callback;
  }

  @override
  Future<void> sendReport(int reportId, ByteData data) async {
    final request = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final responseCommand = Pn532Command.fromValue(request[7])!;
    final packet = Pn532Packet(
      direction: 0xD5,
      command: responseCommand,
      payload: [0],
    ).toList();
    packet[6] = responseCommand.toInt() + 1;
    var checksum = 0xD5 + packet[6] + packet[7];
    packet[8] = (~checksum & 0xFF) + 1;
    final response = Uint8List.fromList([0xE2, ...packet]);
    _inputReportCallback?.call(
      HIDInputReportEvent(0, ByteData.sublistView(response)),
    );
  }
}

class _ScriptedTagHidDevice implements HIDDevice {
  Function(HIDInputReportEvent)? _inputReportCallback;

  @override
  List<HIDCollectionInfo> get collections => const [];

  @override
  bool get opened => true;

  @override
  int get productId => 0;

  @override
  String get productName => 'test';

  @override
  int get vendorId => 0;

  @override
  Future<void> close() async {}

  @override
  Future<void> open() async {}

  @override
  void onInputReport(Function(HIDInputReportEvent)? callback) {
    _inputReportCallback = callback;
  }

  @override
  Future<void> sendReport(int reportId, ByteData data) async {
    final request = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final command = Pn532Command.fromValue(request[7])!;
    final payload = switch (command) {
      Pn532Command.inListPassiveTarget => _pollResponse(request[9]),
      Pn532Command.inDataExchange => [0x14],
      _ => [0],
    };
    final packet = Pn532Packet(
      direction: 0xD5,
      command: command,
      payload: payload,
    ).toList();
    packet[6] = command.toInt() + 1;
    var checksum = 0xD5 + packet[6];
    for (final byte in payload) {
      checksum += byte;
    }
    packet[7 + payload.length] = (~checksum & 0xFF) + 1;
    final response = Uint8List.fromList([0xE2, ...packet]);
    _inputReportCallback?.call(
      HIDInputReportEvent(0, ByteData.sublistView(response)),
    );
  }

  List<int> _pollResponse(int brty) {
    if (brty != 0) {
      return [0];
    }
    return [1, 1, 0x04, 0x00, 0x00, 4, 1, 2, 3, 4];
  }
}

void main() {
  test('uses the Standard Type A RF profiles in order', () {
    expect(
      typeARfProfilesForProductId(
        0x0147,
      ).map((profile) => (profile.rfCfg, profile.cwGsNOn, profile.cwGsP)),
      const [(0x59, 0x0F, 0x3F), (0x69, 0x0F, 0x2B)],
    );
  });

  test('uses the measured Lite Type A RF profiles in order', () {
    expect(
      typeARfProfilesForProductId(
        0x0148,
      ).map((profile) => (profile.rfCfg, profile.cwGsNOn, profile.cwGsP)),
      const [(0x29, 0x03, 0x11), (0x49, 0x0B, 0x0C), (0x59, 0x0F, 0x3F)],
    );
  });

  test('uses only the PN532 default profile for unknown products', () {
    expect(
      typeARfProfilesForProductId(
        0,
      ).map((profile) => (profile.rfCfg, profile.cwGsNOn, profile.cwGsP)),
      const [(0x59, 0x0F, 0x3F)],
    );
  });

  test('uses the USB product id as device id', () {
    final device = UsbHinataDeviceImpl(HinataReader(_NoTagHidDevice()));

    expect(device.deviceId, '0');
    device.dispose();
  });

  test('reports no target explicitly', () async {
    final device = UsbHinataDeviceImpl(HinataReader(_NoTagHidDevice()));

    final result = await device.pollResult();

    expect(result.status, CardReadStatus.noTarget);
    expect(result.card, isNull);
    device.dispose();
  });

  test(
    'requires two complete reads before exposing unsupported Type A',
    () async {
      final device = UsbHinataDeviceImpl(HinataReader(_ScriptedTagHidDevice()));

      final first = await device.pollResult();
      final second = await device.pollResult();
      final third = await device.pollResult();

      expect(first.status, CardReadStatus.incomplete);
      expect(first.card, isNull);
      expect(second.status, CardReadStatus.confirmedUnsupported);
      expect(second.card?.card, isA<Iso14443>());
      expect(second.card?.isUsable, isFalse);
      expect(third.status, CardReadStatus.confirmedUnsupported);
      expect(third.card?.isUsable, isFalse);
      device.dispose();
    },
  );
}
