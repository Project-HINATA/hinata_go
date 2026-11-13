import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

/// A reader whose firmware splits PN532 frames over HID reports: it joins
/// what the host sends and answers InDataExchange with [response] after an
/// ACK, 62 frame bytes to a report.
class _LongFrameHidDevice implements HIDDevice {
  final List<int> response;
  final Queue<List<int>> chainedResponses;
  Function(HIDInputReportEvent)? _callback;

  /// Each frame the host sent, joined from its reports.
  final frames = <List<int>>[];

  /// The command byte of every report the host sent.
  final commands = <int>[];
  final _frame = <int>[];

  _LongFrameHidDevice(
    this.response, {
    Iterable<List<int>> chainedResponses = const [],
  }) : chainedResponses = Queue.of(chainedResponses);

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
    _callback = callback;
  }

  @override
  Future<void> sendReport(int reportId, ByteData data) async {
    final report = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    commands.add(report[0]);
    if (report[0] == 0xEC) {
      var pos = 1;
      while (pos + 5 <= report.length &&
          report[pos] == 0x00 &&
          report[pos + 1] == 0x00 &&
          report[pos + 2] == 0xFF) {
        final len = report[pos + 3] + 7;
        frames.add(report.sublist(pos, pos + len));
        pos += len;
        _send(const [0, 0, 0xFF, 0, 0xFF, 0]);
        final next = chainedResponses.removeFirst();
        _send([...next, ...List.filled(62 - next.length, 0)]);
      }
      return;
    }
    if (report[0] == 0xE2) {
      _frame
        ..clear()
        ..addAll(report.skip(1));
    } else if (report[0] == 0xEB) {
      _frame.addAll(report.skip(2).take(report[1]));
    }
    if (_frame.length < 5 || _frame.length < _frame[3] + 7) return;
    frames.add(List.of(_frame));
    _send(const [0, 0, 0xFF, 0, 0xFF, 0]);
    for (var i = 0; i < response.length; i += 62) {
      final chunk = response.skip(i).take(62).toList();
      _send([...chunk, ...List.filled(62 - chunk.length, 0)]);
    }
  }

  void _send(List<int> bytes) => _callback?.call(
    HIDInputReportEvent(
      3,
      ByteData.sublistView(Uint8List.fromList([0xE2, ...bytes])),
    ),
  );
}

List<int> _frame(int command, List<int> payload) {
  final body = [0xD5, command, ...payload];
  final checksum = -body.fold<int>(0, (sum, b) => sum + b) & 0xFF;
  return [0, 0, 0xFF, body.length, -body.length & 0xFF, ...body, checksum, 0];
}

void main() {
  test('long PN532 frames go out and come back over several reports', () async {
    // A Read Without Encryption answer of eight blocks.
    final blocks = List.generate(8 * 16, (i) => i & 0xFF);
    final device = _LongFrameHidDevice(_frame(0x41, [0x00, ...blocks]));
    final reader = HinataReader(device)..pn532LongFrames = true;
    final data = List.generate(100, (i) => i);

    final payload = await reader.pn532Api.inDataExchange(1, 0x06, data);

    expect(payload, [0x00, ...blocks]);
    // 109 frame bytes: 62 in the passthrough, 47 continued.
    expect(device.commands, [0xE2, 0xEB]);
    final sent = device.frames.single;
    // After the header, D4 40, the target and the data command.
    expect(sent.sublist(9, 9 + data.length), data);
  });

  test('without long frames, a frame goes out in one report', () async {
    final device = _LongFrameHidDevice(_frame(0x41, [0x00, 1, 2]));
    final reader = HinataReader(device);

    final payload = await reader.pn532Api.inDataExchange(1, 0x06, [1, 2, 3]);

    expect(payload, [0x00, 1, 2]);
    expect(device.commands, [0xE2]);
  });

  test(
    'chained PN532 frames pack WriteRegister and TgResponseToInitiator in one 0xEC report',
    () async {
      final device = _LongFrameHidDevice(
        const [],
        chainedResponses: [
          _frame(0x09, const []),
          _frame(0x91, const [0x00]),
        ],
      );
      final reader = HinataReader(device)..pn532Chain = true;

      await reader.pn532Api.writeRegistersAndRespondToInitiator(
        const [(0x633D, 0x04)],
        const [0x11, 0x22, 0x33, 0x44, 0x05],
      );

      expect(device.commands, [0xEC]);
      expect(device.frames, hasLength(2));
      expect(device.frames[0].sublist(5, 10), [0xD4, 0x08, 0x63, 0x3D, 0x04]);
      expect(device.frames[1].sublist(5, 12), [
        0xD4,
        0x90,
        0x11,
        0x22,
        0x33,
        0x44,
        0x05,
      ]);
    },
  );
}
