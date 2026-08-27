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

  test('reads and decodes SFI 0x18 transit records with Shanghai and Hangzhou stations', () async {
    // 0x18 Record 1: Shanghai Metro Line 1 Xinzhuang (31 01 11 74 43 02), 300 cents, Ride
    final record1 = <int>[
      0x00, 0x01, // seq 1
      0x00, 0x00, 0x00, // overdraft
      0x00, 0x00, 0x01, 0x2C, // amount 300 cents (3.00 CNY)
      0x09, // type Ride
      0x31, 0x01, 0x11, 0x74, 0x43, 0x02, // terminalId Shanghai Line 1 Xinzhuang
      0x20, 0x23, 0x08, 0x15, // date 20230815
      0x18, 0x30, 0x00, // time 183000
      0x90, 0x00, // SW 9000
    ];

    // 0x18 Record 2: Hangzhou Metro Line 4 Citizen Center (41 31 01 78 48 16), 200 cents, Ride
    final record2 = <int>[
      0x00, 0x02, // seq 2
      0x00, 0x00, 0x00, // overdraft
      0x00, 0x00, 0x00, 0xC8, // amount 200 cents (2.00 CNY)
      0x09, // type Ride
      0x41, 0x31, 0x01, 0x78, 0x48, 0x16, // terminalId Hangzhou Citizen Center
      0x20, 0x23, 0x08, 0x16, // date 20230816
      0x08, 0x15, 0x00, // time 081500
      0x90, 0x00, // SW 9000
    ];

    final read18Rec1 = <int>[0x00, 0xB2, 0x01, 0xC4, 0x00];
    final read18Rec2 = <int>[0x00, 0xB2, 0x02, 0xC4, 0x00];
    final read18Rec3 = <int>[0x00, 0xB2, 0x03, 0xC4, 0x00];

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

    final read1ERec1_30 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x30];
    final read1ERec1_00 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x00];
    final read18Rec1_17 = <int>[0x00, 0xB2, 0x01, 0xC4, 0x17];
    final read18Rec2_17 = <int>[0x00, 0xB2, 0x02, 0xC4, 0x17];
    final read18Rec3_17 = <int>[0x00, 0xB2, 0x03, 0xC4, 0x17];

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [shanghaiInfo],
      _readBalance: [
        [0, 0, 0x04, 0x00, 0x90, 0x00],
      ],
      read1ERec1_30: [[0x6A, 0x82]], // SFI 0x1E not supported on this card
      read1ERec1_00: [[0x6A, 0x82]],
      read18Rec1_17: [record1],
      read18Rec2_17: [record2],
      read18Rec3_17: [[0x6A, 0x83]], // Record not found / end of records
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: true);

expect(result.status, CardReadStatus.recognized);
    final card = result.card?.card;
    expect(card, isA<TUnion>());
    final tunion = card as TUnion;
    expect(tunion.name, '上海公共交通卡');
    expect(tunion.tags, ['上海公共交通卡', '交通联合', 'ISO-DEP']);
    expect(tunion.transactions.length, 2);
  });

  test('reads and decodes SFI 0x1E JT/T 978 48-byte composite records with entry and exit stations', () async {
    // 0x1E Record 1: Luoyang Metro exit tap (Qingniangong, 3.00 CNY)
    final record1E_1 = <int>[
      0x04, // 0x00: typeCode (Exit)
      0x41, 0x31, 0x06, 0x23, 0x10, 0x94, 0x00, 0x00, // 0x01..0x09: terminalId
      0x01, // 0x09: industry (0x01 = Metro)
      0x01, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, // 0x0A..0x11: station 010014 (Qingniangong)
      0x00, 0x00, 0x01, 0x2C, // 0x11..0x15: amount 300 cents (3.00 CNY)
      0x00, 0x00, 0x03, 0xE8, // 0x15..0x19: balance 1000 cents
      0x20, 0x25, 0x12, 0x21, 0x11, 0x32, 0x14, // 0x19..0x20: timestamp 20251221113214
      0x49, 0x30, // 0x20..0x22: city Luoyang (4930)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x22..0x2A: acquirerId
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x2A..0x30: reserved
      0x90, 0x00, // SW 9000
    ];

    // 0x1E Record 2: Luoyang Metro entry tap (Qilihe, 0.00 CNY)
    final record1E_2 = <int>[
      0x03, // 0x00: typeCode (Entry)
      0x41, 0x31, 0x06, 0x23, 0x10, 0x94, 0x00, 0x00, // 0x01..0x09: terminalId
      0x01, // 0x09: industry (0x01 = Metro)
      0x01, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, // 0x0A..0x11: station 010008 (Qilihe)
      0x00, 0x00, 0x00, 0x00, // 0x11..0x15: amount 0 cents (0.00 CNY)
      0x00, 0x00, 0x03, 0xE8, // 0x15..0x19: balance 1000 cents
      0x20, 0x25, 0x12, 0x21, 0x10, 0x15, 0x30, // 0x19..0x20: timestamp 20251221101530
      0x49, 0x30, // 0x20..0x22: city Luoyang (4930)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x22..0x2A: acquirerId
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x2A..0x30: reserved
      0x90, 0x00, // SW 9000
    ];

    final read1ERec1_30 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x30];
    final read1ERec2_30 = <int>[0x00, 0xB2, 0x02, 0xF4, 0x30];
    final read1ERec3_30 = <int>[0x00, 0xB2, 0x03, 0xF4, 0x30];

    final dalianInfo = _successResponse(32);
    // Card Number: 31051200019246251520 (Dalian Mingzhu Card, IIN 31051200)
    dalianInfo[10] = 0x31;
    dalianInfo[11] = 0x05;
    dalianInfo[12] = 0x12;
    dalianInfo[13] = 0x00;
    dalianInfo[14] = 0x01;
    dalianInfo[15] = 0x92;
    dalianInfo[16] = 0x46;
    dalianInfo[17] = 0x25;
    dalianInfo[18] = 0x15;
    dalianInfo[19] = 0x20;

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [dalianInfo],
      _readBalance: [
        [0, 0, 0x00, 0x0A, 0x90, 0x00], // 0.10 CNY
      ],
      read1ERec1_30: [record1E_1],
      read1ERec2_30: [record1E_2],
      read1ERec3_30: [[0x6A, 0x83]], // End of records
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: true);

    expect(result.status, CardReadStatus.recognized);
    final card = result.card?.card;
    expect(card, isA<TUnion>());
    final tunion = card as TUnion;
    expect(tunion.name, '大连明珠卡');
    expect(tunion.tags, ['大连明珠卡', '交通联合', 'ISO-DEP']);
    expect(tunion.transactions.length, 2);

    final tx1 = tunion.transactions[0];
    expect(tx1.type, 'Ride');
    expect(tx1.amount, -3.00);
    expect(tx1.details, '[洛阳地铁] 1号线 青年宫 (乘出)');

    final tx2 = tunion.transactions[1];
    expect(tx2.type, 'Ride');
    expect(tx2.amount, 0.00);
    expect(tx2.details, '[洛阳地铁] 1号线 七里河 (乘入)');
  });

  test('falls back to SFI 0x18 when SFI 0x1E is not supported', () async {
    // 0x18 Record:
    // seq: 0x0002, amount: 200 cents, type: 0x09 (Ride),
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

    final read1ERec1_30 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x30];
    final read1ERec1_00 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x00];
    final read18Rec1_17 = <int>[0x00, 0xB2, 0x01, 0xC4, 0x17];
    final read18Rec2_17 = <int>[0x00, 0xB2, 0x02, 0xC4, 0x17];

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [_infoResponse()],
      _readBalance: [
        [0, 0, 0x02, 0x00, 0x90, 0x00],
      ],
      read1ERec1_30: [[0x6A, 0x82]], // SFI 0x1E not supported
      read1ERec1_00: [[0x6A, 0x82]],
      read18Rec1_17: [record18],
      read18Rec2_17: [[0x6A, 0x83]],
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

  test('handles 6C <La> wrong Le status word and auto retries with Le = La', () async {
    final record1E = <int>[
      0x03, // 0x00: typeCode (Entry)
      0x41, 0x31, 0x06, 0x23, 0x14, 0x96, 0x00, 0x00, // 0x01..0x09: terminalId
      0x01, // 0x09: industry (0x01 = Metro)
      0x01, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, // 0x0A..0x11: station 010008 (Qilihe)
      0x00, 0x00, 0x00, 0x00, // 0x11..0x15: amount 0 cents
      0x00, 0x00, 0x05, 0x14, // 0x15..0x19: balance 1300 cents
      0x20, 0x25, 0x12, 0x21, 0x11, 0x09, 0x55, // 0x19..0x20: timestamp 20251221110955
      0x49, 0x30, // 0x20..0x22: city Luoyang (4930)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x22..0x2A: acquirerId
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x2A..0x30: reserved
      0x90, 0x00, // SW 9000
    ];

    // Initial probe with Le = 0x00 returns 6C 30
    final read1ERec1_00 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x00];
    final read1ERec1_30 = <int>[0x00, 0xB2, 0x01, 0xF4, 0x30];
    final read1ERec2_30 = <int>[0x00, 0xB2, 0x02, 0xF4, 0x30];

    final channel = _ScriptedChannel({
      _selectAid: [_successResponse(53)],
      _readInfo: [_infoResponse()],
      _readBalance: [
        [0, 0, 0x01, 0x00, 0x90, 0x00],
      ],
      read1ERec1_30: [
        [0x6C, 0x30], // First call returns 6C 30
        record1E, // Auto-retry call returns the data!
      ],
      read1ERec1_00: [[0x6C, 0x30]],
      read1ERec2_30: [[0x6A, 0x83]],
    });

    final result = await CardReaderEngine(
      channel,
    ).processTag(_tag(), readExtended: true);

    expect(result.status, CardReadStatus.recognized);
    final card = result.card?.card as TUnion;
    expect(card.transactions.length, 1);
    expect(card.transactions.first.details, contains('七里河'));
  });
}
