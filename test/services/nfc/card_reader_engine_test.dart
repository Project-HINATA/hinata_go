import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
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

class _MifareFallbackChannel implements NfcCardChannel {
  _MifareFallbackChannel({
    this.failKeyBAuth = false,
    this.failKeyAAuth = false,
    this.failKeyBRead = false,
    this.shortKeyBRead = false,
  });

  final bool failKeyBAuth;
  final bool failKeyAAuth;
  final bool failKeyBRead;
  final bool shortKeyBRead;
  final authKeyKinds = <String>[];
  final readBlocks = <int>[];
  var reconnectCount = 0;

  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) async {
    final keyKind = keyA != null ? 'A' : 'B';
    authKeyKinds.add(keyKind);
    if ((keyKind == 'A' && failKeyAAuth) || (keyKind == 'B' && failKeyBAuth)) {
      throw NfcException(
        type: NfcErrorType.authFailed,
        message: 'scripted Key $keyKind authentication failure',
      );
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> reconnect() async {
    reconnectCount++;
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    readBlocks.add(block);
    if (failKeyBRead && authKeyKinds.last == 'B') {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'scripted Key B read failure',
      );
    }
    if (shortKeyBRead && authKeyKinds.last == 'B') {
      return Uint8List(8);
    }
    return Uint8List(16);
  }

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    throw UnsupportedError('transceive is not part of this test');
  }
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
  test(
    'does not try Key A after Key B authenticated but reading failed',
    () async {
      final channel = _MifareFallbackChannel(failKeyBRead: true);
      final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

      final result = await CardReaderEngine(channel).processTag(tag);

      expect(result.status, CardReadStatus.incomplete);
      expect(channel.authKeyKinds, ['B']);
      expect(channel.reconnectCount, 0);
      expect(channel.readBlocks, [2]);
    },
  );

  test('treats a short MIFARE block as incomplete', () async {
    final channel = _MifareFallbackChannel(shortKeyBRead: true);
    final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

    final result = await CardReaderEngine(channel).processTag(tag);

    expect(result.status, CardReadStatus.incomplete);
    expect(channel.authKeyKinds, ['B']);
    expect(channel.reconnectCount, 0);
  });

  test(
    'tries Key A only after explicit Key B authentication failure',
    () async {
      final channel = _MifareFallbackChannel(failKeyBAuth: true);
      final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

      final result = await CardReaderEngine(channel).processTag(tag);

      expect(result.status, CardReadStatus.confirmedUnsupported);
      expect(result.card?.card, same(tag));
      expect(result.card?.isUsable, isFalse);
      expect(channel.authKeyKinds, ['B', 'A']);
      expect(channel.reconnectCount, 1);
      expect(channel.readBlocks, [1, 2]);
    },
  );

  test(
    'reports unsupported after both keys explicitly reject the card',
    () async {
      final channel = _MifareFallbackChannel(
        failKeyBAuth: true,
        failKeyAAuth: true,
      );
      final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

      final result = await CardReaderEngine(channel).processTag(tag);

      expect(result.status, CardReadStatus.confirmedUnsupported);
      expect(result.card?.card, same(tag));
      expect(result.card?.isUsable, isFalse);
      expect(channel.authKeyKinds, ['B', 'A']);
      expect(channel.readBlocks, isEmpty);
    },
  );

  test('reports a non-MIFARE non-ISO-DEP Type A card as unsupported', () async {
    final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x00, 0x04);

    final result = await CardReaderEngine(
      _MifareFallbackChannel(),
    ).processTag(tag);

    expect(result.status, CardReadStatus.confirmedUnsupported);
    expect(result.card?.card, same(tag));
    expect(result.card?.isUsable, isFalse);
  });

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

    expect(result.status, CardReadStatus.recognized);
    expect(result.card?.card, isA<TUnion>());
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
      ).processTag(_tag(), readExtended: true, existingCard: basic.card);

      expect(basic.card?.card, isA<TUnion>());
      expect(extended.status, CardReadStatus.recognized);
      expect(extended.card, same(basic.card));
    },
  );

  test('reports an explicit T-Union AID rejection as unsupported', () async {
    final channel = _ScriptedChannel({
      _selectAid: [
        [0x6A, 0x82],
      ],
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: false);

    expect(result.status, CardReadStatus.confirmedUnsupported);
    expect(result.card?.card, isA<Iso14443>());
    expect(result.card?.isUsable, isFalse);
  });
}
