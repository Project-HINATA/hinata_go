import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

List<int> _response(Pn532Command command, List<int> payload) {
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
  return packet;
}

void main() {
  test('MIFARE authentication preserves transport timeout type', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) => throw TimeoutException('test timeout'),
    );
    final channel = HinataNfcCardChannel(api);

    try {
      await channel.authenticateMifare(
        uid: Uint8List.fromList([1, 2, 3, 4]),
        block: 2,
        keyB: Uint8List(6),
      );
      fail('authentication should throw');
    } on NfcException catch (error) {
      expect(error.type, NfcErrorType.timeout);
    }
  });

  test('MIFARE reconnect polls Type A without releasing first', () async {
    final writes = <List<int>>[];
    final responses = <List<int>>[
      _response(Pn532Command.inListPassiveTarget, [
        1,
        1,
        0x00,
        0x04,
        0x08,
        4,
        1,
        2,
        3,
        4,
      ]),
    ];
    final api = Pn532Api(
      (data) async => writes.add(List<int>.from(data)),
      ({timeout}) async => responses.removeAt(0),
    );

    await HinataNfcCardChannel(api).reconnect();

    expect(writes.map((packet) => packet[6]), [
      Pn532Command.inListPassiveTarget.toInt(),
    ]);
  });

  test('MIFARE reconnect rejects an absent target', () async {
    final responses = <List<int>>[
      _response(Pn532Command.inListPassiveTarget, [0]),
    ];
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => responses.removeAt(0),
    );

    await expectLater(
      HinataNfcCardChannel(api).reconnect(),
      throwsA(
        isA<NfcException>().having(
          (error) => error.type,
          'type',
          NfcErrorType.readError,
        ),
      ),
    );
  });

  test('MIFARE reconnect rejects a target with a different UID', () async {
    final responses = <List<int>>[
      _response(Pn532Command.inListPassiveTarget, [
        1,
        1,
        0x00,
        0x04,
        0x08,
        4,
        1,
        2,
        3,
        4,
      ]),
    ];
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => responses.removeAt(0),
    );

    await expectLater(
      HinataNfcCardChannel(
        api,
        expectedUid: Uint8List.fromList([4, 3, 2, 1]),
      ).reconnect(),
      throwsA(
        isA<NfcException>().having(
          (error) => error.type,
          'type',
          NfcErrorType.readError,
        ),
      ),
    );
  });

  test('Type A RF settings include receiver gain and conductance', () async {
    final writes = <List<int>>[];
    final api = Pn532Api(
      (data) async => writes.add(List<int>.from(data)),
      ({timeout}) async => _response(Pn532Command.rfConfiguration, const []),
    );

    await api.setTypeARfPower(rfCfg: 0x29, cwGsNOn: 0x03, cwGsP: 0x11);

    expect(writes, hasLength(1));
    expect(writes.single[6], Pn532Command.rfConfiguration.toInt());
    expect(writes.single.sublist(7, 19), [
      0x0A,
      0x29,
      0x34,
      0x11,
      0x11,
      0x4D,
      0x85,
      0x61,
      0x6F,
      0x26,
      0x62,
      0x87,
    ]);
  });

  test('inListPassiveTarget propagates transport timeout', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) => throw TimeoutException('test timeout'),
    );

    await expectLater(
      api.inListPassiveTarget(0, 1, const []),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('inListPassiveTarget'),
            contains('brty=0'),
            contains('after 0 frame(s)'),
          ),
        ),
      ),
    );
  });

  test('timeout reports an ACK received before the final response', () async {
    var readCount = 0;
    final api = Pn532Api((_) async {}, ({timeout}) async {
      if (readCount++ == 0) return standardAck;
      throw TimeoutException('test timeout');
    });

    await expectLater(
      api.inListPassiveTarget(1, 1, const []),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          allOf(contains('brty=1'), contains('after 1 frame(s)')),
        ),
      ),
    );
  });

  test('inListPassiveTarget uses a 1000ms transport timeout', () async {
    Duration? receivedTimeout;
    final api = Pn532Api((_) async {}, ({timeout}) async {
      receivedTimeout = timeout;
      return _response(Pn532Command.inListPassiveTarget, []);
    });

    await api.inListPassiveTarget(0, 1, const []);

    expect(receivedTimeout, const Duration(milliseconds: 1000));
  });

  test('PN532 request ignores a response for another command', () async {
    final responses = <List<int>>[
      standardAck,
      _response(Pn532Command.rfConfiguration, const []),
      _response(Pn532Command.inListPassiveTarget, const [0]),
    ];
    var completed = false;
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => responses.removeAt(0),
      onComplete: () => completed = true,
    );

    expect(await api.inListPassiveTarget(0, 1, const []), isEmpty);
    expect(responses, isEmpty);
    expect(completed, isTrue);
  });

  test('inListPassiveTarget rejects a malformed response', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => [0, 0, 0xFF, 3, 0, 0xD5, 0x4B, 0],
    );

    await expectLater(api.inListPassiveTarget(0, 1, const []), throwsException);
  });

  test(
    'inListPassiveTarget accepts an explicit zero-target response',
    () async {
      final api = Pn532Api(
        (_) async {},
        ({timeout}) async => _response(Pn532Command.inListPassiveTarget, [0]),
      );

      expect(await api.inListPassiveTarget(0, 1, const []), isEmpty);
    },
  );

  test('inListPassiveTarget accepts an empty no-target payload', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => _response(Pn532Command.inListPassiveTarget, []),
    );

    expect(await api.inListPassiveTarget(0, 1, const []), isEmpty);
  });

  test('inListPassiveTarget rejects a truncated target payload', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) async => _response(Pn532Command.inListPassiveTarget, [1]),
    );

    await expectLater(
      api.inListPassiveTarget(0, 1, const []),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'inListPassiveTarget accepts a complete FeliCa system-code payload',
    (() async {
      final api = Pn532Api(
        (_) async {},
        ({timeout}) async => _response(Pn532Command.inListPassiveTarget, [
          1,
          1,
          20,
          1,
          1,
          18,
          2,
          18,
          228,
          35,
          239,
          29,
          5,
          49,
          67,
          69,
          70,
          130,
          183,
          255,
          0,
          3,
        ]),
      );

      final tags = await api.inListPassiveTarget(1, 1, const []);

      expect(tags, hasLength(1));
      expect(tags.single.id, [1, 18, 2, 18, 228, 35, 239, 29]);
      expect(tags.single.pmm, [5, 49, 67, 69, 70, 130, 183, 255]);
      expect(tags.single.systemCodes, [0x0003]);
    }),
  );
}
