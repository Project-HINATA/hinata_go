import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/services/nfc/card_reader_engine.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

const _selectAid = <int>[
  0x00,
  0xA4,
  0x04,
  0x00,
  0x08,
  0xA0,
  0x00,
  0x00,
  0x06,
  0x32,
  0x01,
  0x01,
  0x05,
];

const _readInfo = <int>[0x00, 0xB0, 0x95, 0x00, 0x1E];
const _readBalance = <int>[0x80, 0x5C, 0x00, 0x02, 0x04];

class _ScriptedChannel implements NfcCardChannel {
  final Map<String, List<Uint8List>> _responses = {};
  final Map<String, int> callCounts = {};

  _ScriptedChannel(Map<List<int>, List<List<int>>> responses) {
    for (final entry in responses.entries) {
      _responses[_key(entry.key)] = entry.value
          .map(Uint8List.fromList)
          .toList();
    }
  }

  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> reconnect() async {}

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    throw UnsupportedError('Mifare is not part of this test');
  }

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    final key = _key(data);
    callCounts[key] = (callCounts[key] ?? 0) + 1;
    final responses = _responses[key];
    if (responses == null || responses.isEmpty) {
      throw StateError('No scripted response for $key');
    }
    return responses.removeAt(0);
  }

  static String _key(List<int> data) => data.join(',');
}

Iso14443 _tag() =>
    Iso14443(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]), 0x20, 0x44);

List<int> _successResponse(int length) {
  final response = List<int>.filled(length, 0);
  response[length - 2] = 0x90;
  response[length - 1] = 0x00;
  return response;
}

List<int> _infoResponse() {
  final response = _successResponse(32);
  for (var i = 10; i < 20; i++) {
    response[i] = i - 9;
  }
  return response;
}

Map<List<int>, List<List<int>>> _basicResponses() {
  return {
    _selectAid: [_successResponse(53)],
    _readInfo: [_infoResponse()],
    _readBalance: [
      [0, 0, 0, 100, 0x90, 0x00],
    ],
  };
}

void main() {
  test('retries a transient empty T-Union info response', () async {
    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [Uint8List(0), _infoResponse()],
      _readBalance: [
        [0, 0, 0, 100, 0x90, 0x00],
      ],
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: false);

    expect(result?.card, isA<TUnion>());
    expect(channel.callCounts[_ScriptedChannel._key(_readInfo)], 2);
  });

  test(
    'keeps the basic T-Union card when extended info cannot be read',
    () async {
      final basic = await CardReaderEngine(
        _ScriptedChannel(_basicResponses()),
      ).processTag(_tag(), readExtended: false);

      final extensionChannel = _ScriptedChannel({
        _selectAid: [_successResponse(53)],
        _readInfo: List<List<int>>.generate(5, (_) => const []),
      });
      final extended = await CardReaderEngine(
        extensionChannel,
      ).processTag(_tag(), readExtended: true, existingCard: basic);

      expect(basic?.card, isA<TUnion>());
      expect(extended, same(basic));
    },
  );
}
