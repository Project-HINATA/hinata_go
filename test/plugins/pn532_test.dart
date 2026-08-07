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

  test('inListPassiveTarget propagates transport timeout', () async {
    final api = Pn532Api(
      (_) async {},
      ({timeout}) => throw TimeoutException('test timeout'),
    );

    await expectLater(
      api.inListPassiveTarget(0, 1, const []),
      throwsA(isA<TimeoutException>()),
    );
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
}
