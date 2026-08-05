import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';
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
    final requestCommand = request.length > 7
        ? Pn532Command.fromValue(request[7])
        : null;
    final responseCommand = requestCommand == Pn532Command.inRelease
        ? Pn532Command.inRelease
        : Pn532Command.inListPassiveTarget;
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

void main() {
  test(
    'poll prints the number of calls made during the previous second',
    () async {
      final messages = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.contains('poll calls per second') ?? false) {
          messages.add(message!);
        }
      };

      final device = UsbHinataDeviceImpl(HinataReader(_NoTagHidDevice()));
      try {
        await device.poll();
        await Future<void>.delayed(const Duration(seconds: 1));
        await device.poll();

        expect(messages, ['[UsbHinataDeviceImpl] poll calls per second: 2']);
      } finally {
        debugPrint = previousDebugPrint;
        device.dispose();
      }
    },
  );
}
