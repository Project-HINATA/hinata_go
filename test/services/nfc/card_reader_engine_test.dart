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
    this.keyBReadFailures = 0,
    this.shortKeyBRead = false,
  });

  final bool failKeyBAuth;
  final bool failKeyAAuth;
  int keyBReadFailures;
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
    if (keyBReadFailures > 0 && authKeyKinds.last == 'B') {
      keyBReadFailures--;
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
      final channel = _MifareFallbackChannel(keyBReadFailures: 2);
      final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

      final result = await CardReaderEngine(channel).processTag(tag);

      expect(result.status, CardReadStatus.incomplete);
      expect(channel.authKeyKinds, ['B', 'B']);
      expect(channel.reconnectCount, 1);
      expect(channel.readBlocks, [2, 2]);
    },
  );

  test('fast retries a transient Key B block read failure', () async {
    final channel = _MifareFallbackChannel(keyBReadFailures: 1);
    final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x04);

    final result = await CardReaderEngine(channel).processTag(tag);

    expect(result.status, CardReadStatus.recognized);
    expect(channel.authKeyKinds, ['B', 'B']);
    expect(channel.reconnectCount, 1);
    expect(channel.readBlocks, [2, 2]);
  });

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

  test('reads and decodes SFI 0x1E transit composite records with stations', () async {
    // 48-byte SFI 0x1E record:
    // seq: 0x0001, type: 0x09 (Ride), termId: 010203040506, amount: 300 cents (00 00 01 2C),
    // date: 20 23 08 15, time: 18 30 00,
    // cityCode: 29 00 (Shanghai), industryCode: 00 02 (Metro),
    // stationCode: 00 01 00 11 (Line 1 Xinzhuang)
    // entryCityCode: 29 00, entryIndustry: 00 02, entryTermId: 00 00 00 00 00 00
    // entryStation: 00 01 00 23 (Line 1 People's Square)
    final record1E = <int>[
      0x00, 0x01, // seq 1
      0x09, 0x00, // type Ride
      0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // terminalId
      0x00, 0x00, 0x01, 0x2C, // amount 300
      0x20, 0x23, 0x08, 0x15, // date 20230815
      0x18, 0x30, 0x00, // time 183000
      0x29, 0x00, // city Shanghai (2900)
      0x00, 0x02, // industry Metro
      0x00, 0x01, 0x00, 0x11, // exit station 00010011 (Xinzhuang)
      0x29, 0x00, // entry city Shanghai (2900)
      0x00, 0x02, // entry industry
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // entry term
      0x00, 0x01, 0x00, 0x23, // entry station 00010023 (People's Square)
      0x20, 0x23, 0x08, 0x15, // entry date
      0x18, 0x00, 0x00, // entry time
      0x90, 0x00, // SW 9000
    ];

    final read1ERec1 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x00];
    final read1ERec2 = <int>[0x00, 0xB2, 0x02, 0xF4, 0x00];

    // Info response with Shanghai IIN: 31 04 77 00 12 34 56 78 90 00
    final shanghaiInfo = _successResponse(32);
    shanghaiInfo[10] = 0x31;
    shanghaiInfo[11] = 0x04;
    shanghaiInfo[12] = 0x77;
    shanghaiInfo[13] = 0x00;
    shanghaiInfo[14] = 0x12;
    shanghaiInfo[15] = 0x34;
    shanghaiInfo[16] = 0x56;
    shanghaiInfo[17] = 0x78;
    shanghaiInfo[18] = 0x90;
    shanghaiInfo[19] = 0x00;

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [shanghaiInfo],
      _readBalance: [
        [0, 0, 0x04, 0x00, 0x90, 0x00],
      ],
      read1ERec1: [record1E],
      read1ERec2: [[0x6A, 0x83]], // Record not found / end of records
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: true);

    expect(result.status, CardReadStatus.recognized);
    final card = result.card?.card;
    expect(card, isA<TUnion>());
    final tunion = card as TUnion;
    expect(tunion.name, '上海公共交通卡');
    expect(tunion.transactions.length, 1);
    final tx = tunion.transactions.first;
    expect(tx.type, 'Ride');
    expect(tx.amount, -3.00);
    expect(tx.details, contains('[上海地铁]'));
    expect(tx.details, contains('人民广场 ──► 莘庄'));
  });

  test('falls back to SFI 0x18 and decodes terminal IDs when 0x1E is unavailable', () async {
    // 0x18 Record:
    // seq: 0x0002, overrun: 00 00 00, amount: 200 cents, type: 0x09 (Ride),
    // terminalId: 41 31 01 78 48 16 (Hangzhou POS: Citizen Center),
    // date: 20 23 09 01, time: 08 15 00
    final record18 = <int>[
      0x00, 0x02, // seq 2
      0x00, 0x00, 0x00, // overrun
      0x00, 0x00, 0x00, 0xC8, // amount 200
      0x09, // type Ride
      0x41, 0x31, 0x01, 0x78, 0x48, 0x16, // terminalId
      0x20, 0x23, 0x09, 0x01, // date
      0x08, 0x15, 0x00, // time
      0x90, 0x00, // SW 9000
    ];

    final read1ERec1 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x00];
    final read18Rec1 = <int>[0x00, 0xB2, 0x01, 0xC4, 0x00];
    final read18Rec2 = <int>[0x00, 0xB2, 0x02, 0xC4, 0x00];

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [_infoResponse()],
      _readBalance: [
        [0, 0, 0x02, 0x00, 0x90, 0x00],
      ],
      read1ERec1: [[0x6A, 0x82]], // SFI 0x1E not supported
      read18Rec1: [record18],
      read18Rec2: [[0x6A, 0x83]],
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: true);

    expect(result.status, CardReadStatus.recognized);
    final card = result.card?.card;
    expect(card, isA<TUnion>());
    final tunion = card as TUnion;
    expect(tunion.transactions.length, 1);
    final tx = tunion.transactions.first;
    expect(tx.type, 'Ride');
    expect(tx.amount, -2.00);
    expect(tx.details, '[杭州地铁] 4 市民中心');
  });
}
