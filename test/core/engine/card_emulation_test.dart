import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/crypto/crypto1.dart';
import 'package:hinata_go/core/crypto/mifare_key.dart';
import 'package:hinata_go/core/crypto/spad0.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/core/engine/card_reader_engine.dart';
import 'package:hinata_go/core/engine/felica_dump_reader.dart';
import 'package:hinata_go/core/engine/felica_tag.dart';
import 'package:hinata_go/core/engine/mifare_classic_tag.dart';
import 'package:hinata_go/core/engine/type3_ndef_tag.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:ndef/ndef.dart' as ndef;

/// Hands length-prefixed FeliCa frames to an emulated card.
class _FelicaTagChannel implements NfcCardChannel {
  final FelicaTag tag;

  /// The command codes sent, in order.
  final commands = <int>[];

  /// How many commands are answered before the card leaves the field.
  int? answers;

  _FelicaTagChannel(this.tag, {this.answers});

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    final left = answers;
    if (left != null) {
      if (left == 0) throw StateError('Card left');
      answers = left - 1;
    }
    expect(data[0], data.length);
    commands.add(data[1]);
    final response = tag.process(Uint8List.sublistView(data, 1));
    if (response == null) throw StateError('No response');
    return Uint8List.fromList([response.length + 1, ...response]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A card that does not answer Request System Code.
class _UnlistedChannel extends _FelicaTagChannel {
  _UnlistedChannel(super.tag);

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) {
    if (data[1] == 0x0C) throw TimeoutException('No answer');
    return super.transceive(data, timeout: timeout);
  }
}

/// Simulates a MIFARE Classic reader talking to [MifareClassicTag].
class _MifareSimReader {
  final MifareClassicTag tag;
  late final int _uid =
      (tag.uid[0] << 24) | (tag.uid[1] << 16) | (tag.uid[2] << 8) | tag.uid[3];
  Crypto1? _crypto;
  var _started = false;

  _MifareSimReader(this.tag);

  MifareFrame? _sendPlain(List<int> cmd) {
    if (!_started) {
      _started = true;
      return tag.first(Uint8List.fromList(cmd));
    }
    final raw = [...cmd, ...crcA(cmd)];
    final par = [for (final b in raw) oddParity8(b)];
    return tag.handle(packParity(raw, par).$1);
  }

  MifareFrame? _sendCrypt(List<int> plain, {bool crc = true}) {
    final crypto = _crypto!;
    final data = crc ? [...plain, ...crcA(plain)] : plain;
    final enc = <int>[];
    final par = <int>[];
    for (final b in data) {
      final ks = crypto.byte();
      enc.add(b ^ ks);
      par.add(oddParity8(b) ^ crypto.peek());
    }
    return tag.handle(packParity(enc, par).$1);
  }

  (Uint8List, List<int>) _decrypt(Uint8List packed, int nbytes) {
    final crypto = _crypto!;
    final (enc, par) = unpackParity(packed, nbytes);
    final plain = Uint8List(nbytes);
    final ok = <int>[];
    for (var i = 0; i < nbytes; i++) {
      final ks = crypto.byte();
      final p = enc[i] ^ ks;
      final expectedPar = oddParity8(p) ^ crypto.peek();
      plain[i] = p;
      ok.add(par[i] == expectedPar ? 1 : 0);
    }
    return (plain, ok);
  }

  int _readNibble(int enc) {
    final crypto = _crypto!;
    var out = enc & 0x0F;
    for (var i = 0; i < 4; i++) {
      out ^= crypto.bit() << i;
    }
    return out;
  }

  bool auth(int cmd, int block, List<int> key, {int nr = 0x12345678}) {
    final nested = _crypto != null;
    final resp = nested ? _sendCrypt([cmd, block]) : _sendPlain([cmd, block]);
    if (resp == null || resp.lastBits != 4) return false;

    final nextCrypto = Crypto1.fromBytes(key);
    int nt;
    if (nested) {
      final (ntEnc, _) = unpackParity(resp.raw, 4);
      final ntEncWord =
          (ntEnc[0] << 24) | (ntEnc[1] << 16) | (ntEnc[2] << 8) | ntEnc[3];
      nt = ntEncWord ^ nextCrypto.word(_uid ^ ntEncWord, true);
    } else {
      final (ntBytes, ntPar) = unpackParity(resp.raw, 4);
      for (var i = 0; i < 4; i++) {
        if (ntPar[i] != oddParity8(ntBytes[i])) return false;
      }
      nt =
          (ntBytes[0] << 24) |
          (ntBytes[1] << 16) |
          (ntBytes[2] << 8) |
          ntBytes[3];
      nextCrypto.word(nt ^ _uid);
    }
    _crypto = nextCrypto;

    final nrEnc = <int>[];
    final nrPar = <int>[];
    for (var i = 3; i >= 0; i--) {
      final b = (nr >> (8 * i)) & 0xFF;
      nrEnc.add(b ^ nextCrypto.byte(b));
      nrPar.add(oddParity8(b) ^ nextCrypto.peek());
    }
    final ar = prngSuccessor(nt, 64);
    final arEnc = <int>[];
    final arPar = <int>[];
    for (var i = 3; i >= 0; i--) {
      final b = (ar >> (8 * i)) & 0xFF;
      arEnc.add(b ^ nextCrypto.byte());
      arPar.add(oddParity8(b) ^ nextCrypto.peek());
    }
    final atExpected = prngSuccessor(ar, 32);

    final atResp = tag.handle(
      packParity([...nrEnc, ...arEnc], [...nrPar, ...arPar]).$1,
    );
    if (atResp == null) {
      _crypto = null;
      return false;
    }
    final (atBytes, ok) = _decrypt(atResp.raw, 4);
    if (ok.contains(0)) return false;
    final at =
        (atBytes[0] << 24) |
        (atBytes[1] << 16) |
        (atBytes[2] << 8) |
        atBytes[3];
    return at == atExpected;
  }

  Uint8List? readBlock(int block) {
    final resp = _sendCrypt([0x30, block]);
    if (resp == null || resp.lastBits != 2) return null;
    final (plain, ok) = _decrypt(resp.raw, 18);
    if (ok.contains(0)) return null;
    final body = Uint8List.sublistView(plain, 0, 16);
    final crc = crcA(body);
    if (plain[16] != crc[0] || plain[17] != crc[1]) return null;
    return body;
  }

  bool writeBlock(int block, List<int> data) {
    final resp1 = _sendCrypt([0xA0, block]);
    if (resp1 == null || resp1.lastBits != 4) return false;
    if (_readNibble(resp1.raw[0]) != MifareClassicTag.ack) return false;
    final resp2 = _sendCrypt(data);
    if (resp2 == null || resp2.lastBits != 4) return false;
    return _readNibble(resp2.raw[0]) == MifareClassicTag.ack;
  }

  MifareFrame? halt() {
    final resp = _crypto != null
        ? _sendCrypt(const [0x50, 0x00])
        : _sendPlain(const [0x50, 0x00]);
    _crypto = null;
    _started = false;
    return resp;
  }
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  final idm = _hex('012E0102030405F6');
  final pmm = _hex('00F1000000014300');
  final systemCodes = Uint16List.fromList([0x88B4]);
  final accessCode = _hex('50012345678901234567');

  test('S_PAD0 encryption is the inverse of decryption', () {
    final random = Random(7);
    for (var i = 0; i < 100; i++) {
      final plain = Uint8List.fromList(
        List.generate(16, (_) => random.nextInt(256)),
      );
      expect(spad0Decrypt(spad0Encrypt(plain)), plain);
    }
  });

  test('an emulated Amusement IC reads back as the saved card', () async {
    final saved = Aic.fromAccessCode(idm, pmm, systemCodes, accessCode);
    expect(emulationKindOf(saved), EmulationKind.amusementIc);
    final target = emulationTargetFor(saved, type4MaxRead: 51);
    expect(target.type4, isNull);

    final engine = CardReaderEngine(_FelicaTagChannel(target.felica!));
    // The first batch, S_PAD0 among it, already tells it apart.
    final basic = await engine.handleFelica(
      tag: Felica(idm, pmm, systemCodes),
      readExtended: false,
    );
    expect(basic!.card, isA<Aic>());
    expect(basic.isExtendedInfoFullyLoaded, isFalse);

    final read = await engine.handleFelica(
      tag: Felica(idm, pmm, systemCodes),
      existingCard: basic,
    );

    final card = read!.card;
    expect(card, isA<Aic>());
    expect(read.isExtendedInfoFullyLoaded, isTrue);
    expect((card as Aic).accessCodeString, '50012345678901234567');
    expect(card.id, idm);
    expect(target.felica!.takeMarkerRead(), isTrue);
  });

  test('a FeliCa card answers polling with its saved identity', () {
    final felica = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003, 0xFE00]),
    );
    final tag = emulationTargetFor(felica, type4MaxRead: 51).felica!;

    expect(tag.process(_hex('0000030100')), [
      0x01,
      ...idm,
      ...felica.pmm,
      0x00,
      0x03,
    ]);
    // System 1 answers with its own IDm, the system number in the high
    // nibble of the first byte.
    final system1 = Uint8List.fromList(idm)..[0] = 0x11;
    expect(tag.process(_hex('00FE000100')), [
      0x01,
      ...system1,
      ...felica.pmm,
      0xFE,
      0x00,
    ]);
    expect(tag.process(_hex('0088B40100')), isNull);
    expect(tag.process(Uint8List.fromList([0x0C, ...idm])), [
      0x0D,
      ...idm,
      2,
      0x00,
      0x03,
      0xFE,
      0x00,
    ]);
    // No services were saved, so the card has none to read.
    expect(
      tag.process(
        Uint8List.fromList([0x06, ...idm, 1, 0x0B, 0x00, 1, 0x80, 0]),
      ),
      [0x07, ...idm, 0x01, 0xA6],
    );
  });

  test('a fully read card answers only the blocks it had', () {
    final block = _hex('00112233445566778899AABBCCDDEEFF');
    final felica = Felica(
      idm,
      _hex('0120220427674EFF'),
      systemCodes,
      dump: FelicaDump(
        complete: true,
        systemCode: 0x88B4,
        services: {
          0x090F: {0: block},
        },
      ),
    );
    final tag = emulationTargetFor(felica, type4MaxRead: 51).felica!;
    Uint8List? check(int service, int block) => tag.process(
      Uint8List.fromList([
        0x06,
        ...idm,
        1,
        service & 0xFF,
        service >> 8,
        1,
        0x80,
        block,
      ]),
    );

    expect(check(0x090F, 0), [0x07, ...idm, 0, 0, 1, ...block]);
    // Past the end of the service, and a service the card did not have.
    expect(check(0x090F, 1), [0x07, ...idm, 0x01, 0xA8]);
    expect(check(0x000B, 0), [0x07, ...idm, 0x01, 0xA6]);
  });

  test('a FeliCa card reads back with every block it saved', () async {
    final history = _hex('1602000033A0E3420000E80300000100');
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003]),
      dump: FelicaDump(
        complete: true,
        systemCode: 0x0003,
        services: {
          0x008B: {0: Uint8List(16)},
          0x090F: {0: history, 1: Uint8List(16)},
        },
      ),
    );
    final target = emulationTargetFor(saved, type4MaxRead: 51);
    final engine = CardReaderEngine(_FelicaTagChannel(target.felica!));

    final progress = <ScannedCard>[];
    final read = await engine.handleFelica(
      tag: Felica(idm, saved.pmm, saved.systemCode),
      onProgress: progress.add,
    );

    // The system codes show first, then the history record by record,
    // before the other services are listed and read.
    expect(progress, hasLength(3));
    expect((progress[0].card as Felica).systemCode, [0x0003]);
    final first = progress[1].card as Suica;
    expect(first.balance, 1000);
    expect(first.isFullyRead, isFalse);
    expect(first.dump!.services[0x090F]!.keys, [0]);
    final last = progress.last.card as Suica;
    expect(last.dump!.services.keys, [0x090F]);
    expect(last.dump!.services[0x090F]!.keys, [0, 1]);

    final card = read!.card;
    expect(card, isA<Suica>());
    expect(read.isExtendedInfoFullyLoaded, isTrue);
    expect((card as Suica).balance, 1000);
    // The finished dump keeps the card's order, not the reading order.
    expect(card.dump!.services.keys, [0x008B, 0x090F]);
    expect(card.dump!.blockCount, 3);
    expect(card.dump!.block(0x090F, 0), history);

    final decoded = ICCard.fromJson(card.toJson()) as Suica;
    expect(decoded.balance, 1000);
    expect(decoded.transactions.length, card.transactions.length);
    expect(decoded.isFullyRead, isTrue);
    expect(card.toRemoteJson().containsKey('dump'), isFalse);
  });

  test('every system reads back through its own IDm', () async {
    final history = _hex('1602000033A0E3420000E80300000100');
    final common = Uint8List(16)..fillRange(0, 16, 0x5A);
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003, 0xFE00]),
      dump: FelicaDump.ofSystems(
        complete: true,
        systems: [
          FelicaSystem(
            code: 0x0003,
            services: {
              0x090F: {0: history},
            },
          ),
          FelicaSystem(
            code: 0xFE00,
            services: {
              0x1A8B: {0: common},
            },
          ),
        ],
      ),
    );
    final target = emulationTargetFor(saved, type4MaxRead: 51);
    final engine = CardReaderEngine(_FelicaTagChannel(target.felica!));

    // Polling finds only system 0.
    final read = await engine.handleFelica(
      tag: Felica(idm, saved.pmm, Uint16List.fromList([0x0003])),
    );

    final card = read!.card as Suica;
    expect(read.isExtendedInfoFullyLoaded, isTrue);
    expect(card.systemCode, [0x0003, 0xFE00]);
    expect(card.dump!.systemCodes, [0x0003, 0xFE00]);
    expect(card.dump!.systems[1].services[0x1A8B]![0], common);
    // A system's services answer only to that system's IDm.
    final system1 = Uint8List.fromList(idm)..[0] = 0x11;
    expect(
      target.felica!.process(
        Uint8List.fromList([0x06, ...system1, 1, 0x8B, 0x1A, 1, 0x80, 0]),
      ),
      [0x07, ...system1, 0, 0, 1, ...common],
    );
    expect(
      target.felica!.process(
        Uint8List.fromList([0x06, ...idm, 1, 0x8B, 0x1A, 1, 0x80, 0]),
      ),
      [0x07, ...idm, 0x01, 0xA6],
    );

    final decoded = ICCard.fromJson(card.toJson()) as Suica;
    expect(decoded.dump!.systemCodes, [0x0003, 0xFE00]);
    expect(decoded.dump!.systems[1].services[0x1A8B]![0], common);
  });

  test(
    'the first batch lists the systems, and the card stays a Suica',
    () async {
      final history = _hex('1602000033A0E3420000E80300000100');
      final saved = Felica(
        idm,
        _hex('0120220427674EFF'),
        Uint16List.fromList([0x0003, 0xFE00]),
        dump: FelicaDump.ofSystems(
          complete: true,
          systems: [
            FelicaSystem(
              code: 0x0003,
              services: {
                0x090F: {0: history},
              },
            ),
            FelicaSystem(code: 0xFE00),
          ],
        ),
      );
      final engine = CardReaderEngine(
        _FelicaTagChannel(emulationTargetFor(saved, type4MaxRead: 51).felica!),
      );
      final polled = Felica(idm, saved.pmm, Uint16List.fromList([0x0003]));
      final basic = await engine.handleFelica(tag: polled, readExtended: false);
      // The first batch lists the systems, and its history already makes it
      // a Suica.
      expect(basic!.card, isA<Suica>());
      expect((basic.card as Felica).systemCode, [0x0003, 0xFE00]);
      expect((basic.card as Suica).balance, 1000);

      final channel = engine.transceiver as _FelicaTagChannel;
      channel.commands.clear();
      final progress = <ScannedCard>[];
      await engine.handleFelica(
        tag: polled,
        existingCard: basic,
        onProgress: progress.add,
      );
      // The background read does not list the systems again.
      expect(channel.commands, isNot(contains(0x0C)));

      // Before the history is read again, the card is still the Suica the
      // first read found.
      final codes = progress.first.card as Suica;
      expect(codes.systemCode, [0x0003, 0xFE00]);
      expect(codes.balance, 1000);
    },
  );

  test('a dump saved before systems were kept is the first system', () {
    final card =
        ICCard.fromJson({
              'type': 'felica',
              'id': '012e0102030405f6',
              'pmm': '0120220427674eff',
              'systemCode': [0x0003],
              'dump': {
                'complete': true,
                'services': [
                  {
                    'code': 0x090F,
                    'blocks': {'0': '00112233445566778899aabbccddeeff'},
                  },
                ],
              },
            })
            as Felica;

    expect(card.dump!.systemCodes, [0x0003]);
    expect(
      card.dump!.block(0x090F, 0),
      _hex('00112233445566778899AABBCCDDEEFF'),
    );
  });

  test('blocks are read two at a time', () async {
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003]),
      dump: FelicaDump(
        complete: true,
        services: {
          0x090F: {for (var i = 0; i < 20; i++) i: Uint8List(16)..[0] = i},
        },
        systemCode: 0x0003,
      ),
    );
    final channel = _FelicaTagChannel(
      emulationTargetFor(saved, type4MaxRead: 51).felica!,
    );

    final dump = await FelicaDumpReader(channel).read(saved);

    expect(dump.services[0x090F]!.keys, List.generate(20, (i) => i));
    expect(dump.block(0x090F, 19)![0], 19);
    // Ten reads of two, one past the end, then block 20 alone to find it.
    expect(channel.commands.where((code) => code == 0x06), hasLength(12));
  });

  test('a card that reads fewer blocks at once gets smaller reads', () async {
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003]),
      dump: FelicaDump(
        complete: true,
        services: {
          0x090F: {for (var i = 0; i < 20; i++) i: Uint8List(16)..[0] = i},
        },
        systemCode: 0x0003,
      ),
    );
    final channel = _FelicaTagChannel(
      emulationTargetFor(saved, type4MaxRead: 51, felicaMaxBlocks: 4).felica!,
    );

    final dump = await FelicaDumpReader(channel, blocksPerRead: 8).read(saved);

    expect(dump.services[0x090F]!.keys, List.generate(20, (i) => i));
    // Eight refused, read alone; then reads of four, one past the end, and
    // block 20 alone to find it.
    expect(channel.commands.where((code) => code == 0x06), hasLength(14));
  });

  test('a read that stops early keeps its blocks, marked incomplete', () async {
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      systemCodes,
      dump: FelicaDump(
        complete: true,
        systemCode: 0x88B4,
        services: {
          0x100B: {for (var i = 0; i < 4; i++) i: Uint8List(16)..[0] = i},
        },
      ),
    );
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica!;
    // The system codes, two service searches, then one read of two blocks
    // before the card leaves.
    final channel = _FelicaTagChannel(tag, answers: 4);

    final dump = await FelicaDumpReader(channel).read(saved);

    expect(dump.complete, isFalse);
    expect(dump.services[0x100B]!.keys, [0, 1]);
    expect(dump.isServiceComplete(0x100B), isFalse);
  });

  test(
    'a Suica history read in full stays complete if the card leaves',
    () async {
      final history = _hex('1602000033A0E3420000E80300000100');
      final saved = Felica(
        idm,
        _hex('0120220427674EFF'),
        Uint16List.fromList([0x0003]),
        dump: FelicaDump(
          complete: true,
          systemCode: 0x0003,
          services: {
            0x090F: {0: history},
            0x108F: {0: Uint8List(16), 1: Uint8List(16)},
          },
        ),
      );
      final tag = emulationTargetFor(saved, type4MaxRead: 51).felica!;
      // The system codes, the history: a two-block read past its end, then
      // its one block and its end one at a time; three service searches,
      // then one read of two blocks of the next service before the card
      // leaves.
      final channel = _FelicaTagChannel(tag, answers: 8);

      final read = await CardReaderEngine(
        channel,
      ).handleFelica(tag: Felica(idm, saved.pmm, saved.systemCode));

      final card = read!.card as Suica;
      expect(card.isFullyRead, isFalse);
      expect(card.isHistoryComplete, isTrue);
      expect(card.dump!.services[0x108F]!.keys, [0, 1]);
      final decoded = ICCard.fromJson(card.toJson()) as Suica;
      expect(decoded.isHistoryComplete, isTrue);
      expect(decoded.dump!.isServiceComplete(0x108F), isFalse);
    },
  );

  test('a Lite-S reads back only the blocks it saved', () async {
    final saved = Aic.fromAccessCode(idm, pmm, systemCodes, accessCode);
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica!;

    final dump = await FelicaDumpReader(_FelicaTagChannel(tag)).read(saved);

    // Only S_PAD0 was saved; the other Lite-S blocks are missing.
    expect(dump.complete, isTrue);
    expect(dump.services.keys, [0x000B]);
    expect(dump.services[0x000B]!.keys, [0]);
    expect(dump.block(0x000B, 0), saved.dump!.block(0x000B, 0));
    // The Lite-S read/write service reads the same blocks.
    expect(
      tag.process(
        Uint8List.fromList([0x06, ...idm, 1, 0x09, 0x00, 1, 0x80, 0]),
      ),
      [0x07, ...idm, 0, 0, 1, ...saved.dump!.block(0x000B, 0)!],
    );
    expect(emulationIsPartial(saved), isTrue);
    expect(emulatesLite(saved), isTrue);
  });

  test('a Lite-S emulates its saved MAC and MAC_A as they were read', () {
    final mac = Uint8List(16)..fillRange(0, 16, 0xAB);
    final macA = Uint8List(16)..fillRange(0, 16, 0xCD);
    final saved = Felica(
      idm,
      pmm,
      systemCodes,
      dump: FelicaDump(
        complete: true,
        systemCode: 0x88B4,
        services: {
          0x000B: {0x81: mac, 0x91: macA},
        },
      ),
    );
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica!;
    Uint8List? read(int block) => tag.process(
      Uint8List.fromList([0x06, ...idm, 1, 0x0B, 0x00, 1, 0x80, block]),
    );

    expect(read(0x81), [0x07, ...idm, 0, 0, 1, ...mac]);
    expect(read(0x91), [0x07, ...idm, 0, 0, 1, ...macA]);
    // A Lite-S block that was not saved is missing.
    expect(read(0x82), [0x07, ...idm, 0x01, 0xA8]);
  });

  test('only cards with complete saved data are emulated', () {
    expect(emulationKindOf(NdefCard(_hex('D00000'))), EmulationKind.ndef);
    expect(
      emulationKindOf(Felica(idm, pmm, systemCodes)),
      EmulationKind.felica,
    );
    expect(emulationKindOf(Felica(idm, Uint8List(0), systemCodes)), isNull);
    expect(emulationKindOf(Felica(idm, pmm, Uint16List(0))), isNull);
    expect(
      emulationKindOf(Aic.fromAccessCode(idm, pmm, systemCodes, Uint8List(4))),
      isNull,
    );
    expect(emulationKindOf(Iso14443(_hex('01020304'), 0x08, 0x0004)), isNull);
    expect(
      emulationKindOf(
        Aime(
          accessCode,
          physicalCard: Iso14443(_hex('01020304'), 0x08, 0x0004),
        ),
      ),
      EmulationKind.mifareClassic,
    );
    expect(emulationKindOf(Aime(Uint8List(4))), isNull);
  });

  group('MIFARE Classic emulation', () {
    test('9-bit parity framing round-trips arbitrary byte lengths', () {
      for (final len in [1, 4, 8, 16, 18]) {
        final data = [for (var i = 0; i < len; i++) (i * 37 + 13) & 0xFF];
        final par = [for (var i = 0; i < len; i++) (i * 3) & 1];
        final (packed, lastBits) = packParity(data, par);
        expect(packed.length, (len * 9 + 7) ~/ 8);
        expect(lastBits, (len * 9) & 7);
        final (unpackedData, unpackedPar) = unpackParity(packed, len);
        expect(unpackedData, data);
        expect(unpackedPar, par);
      }
    });

    test(
      'emulates an Aime card with initial auth, read, write discard, and halt',
      () {
        final card = Aime(
          _hex('01234567890123456789'),
          physicalCard: Iso14443(_hex('12345678'), 0x08, 0x0004),
        );
        final target = emulationTargetFor(card, type4MaxRead: 51);
        expect(target.kind, EmulationKind.mifareClassic);
        final tag = target.mifare!;
        // PN532 target mode forces uid[0] = 0x08.
        expect(tag.uid, _hex('08345678'));

        final reader = _MifareSimReader(tag);
        expect(reader.auth(0x61, 3, aimeKey), isTrue);

        final b0 = reader.readBlock(0)!;
        expect(b0.sublist(0, 4), _hex('08345678'));
        expect(b0[4], 0x08 ^ 0x34 ^ 0x56 ^ 0x78);
        expect(tag.takeMarkerRead(), isFalse);

        final b2 = reader.readBlock(2)!;
        expect(b2.sublist(6, 16), _hex('01234567890123456789'));
        expect(tag.takeMarkerRead(), isTrue);
        expect(tag.takeMarkerRead(), isFalse);

        // Trailer read masks Key A and Key B.
        final b3 = reader.readBlock(3)!;
        expect(b3.sublist(0, 6), List.filled(6, 0));
        expect(b3.sublist(10, 16), List.filled(6, 0));

        // Writes are acknowledged when permitted, but discarded.
        final originalB1 = Uint8List.fromList(reader.readBlock(1)!);
        expect(reader.writeBlock(1, List.filled(16, 0xAA)), isTrue);
        expect(reader.readBlock(1), originalB1);

        // Nested authentication into Sector 1 with default key FFFFFFFFFFFF.
        expect(reader.auth(0x60, 4, List.filled(6, 0xFF)), isTrue);
        expect(reader.readBlock(4), List.filled(16, 0));

        expect(reader.halt(), isNull);
      },
    );

    test('emulates single-key and dual-key Banapass cards', () {
      final b1 = _hex('91015098323232323030303030303030');
      final b2 = _hex('00877D00000000000000000000006B04');
      final physical = Iso14443(_hex('11223344'), 0x08, 0x0004);

      final singleKey = Banapass(b1, null, physicalCard: physical);
      expect(emulationKindOf(singleKey), EmulationKind.mifareClassic);
      final singleTag = emulationTargetFor(singleKey, type4MaxRead: 51).mifare!;
      final singleReader = _MifareSimReader(singleTag);
      expect(singleReader.auth(0x60, 1, banaKey), isTrue);
      expect(singleReader.readBlock(1), b1);
      expect(singleTag.takeMarkerRead(), isTrue);

      final dualKey = Banapass(b1, b2, physicalCard: physical);
      expect(emulationKindOf(dualKey), EmulationKind.mifareClassic);
      final dualTag = emulationTargetFor(dualKey, type4MaxRead: 51).mifare!;
      final dualReader = _MifareSimReader(dualTag);
      // Rewritable dual-key Banapass uses Banapass key as Key A and Aime key as Key B.
      expect(dualReader.auth(0x60, 1, banaKey), isTrue);
      expect(dualReader.readBlock(1), b1);
      expect(dualTag.takeMarkerRead(), isTrue);
      expect(dualReader.auth(0x61, 2, aimeKey), isTrue);
      expect(dualReader.readBlock(2), b2);
    });
  });

  group('a FeliCa card holding NDEF', () {
    final message = NdefCard.fromRecords([
      ndef.UriRecord.fromString('https://example.org/${'a' * 60}'),
    ]).message;
    final type3 = Type3NdefTag(message, idm: idm).services[0x000B]!;
    // The rest of a Lite-S, after its NDEF blocks.
    final rest = {
      for (var number = type3.length; number < 14; number++)
        number: Uint8List(16),
      0x88: Uint8List(16)..[3] = 0x01,
    };
    Felica lite({Map<int, Uint8List>? blocks}) => Felica(
      idm,
      pmm,
      Uint16List.fromList([0x88B4]),
      dump: FelicaDump(
        complete: true,
        systemCode: 0x88B4,
        services: {0x000B: blocks ?? type3},
      ),
    );
    Uint8List? poll(FelicaTag tag, int code) => tag.process(
      Uint8List.fromList([0x00, code >> 8, code & 0xFF, 0x01, 0x00]),
    );

    test(
      'a Lite-S polled as 0x12FC is saved as 0x88B4 with its NDEF',
      () async {
        final engine = CardReaderEngine(
          _FelicaTagChannel(
            FelicaTag(
              idm: idm,
              pmm: pmm,
              systemCodes: const [0x88B4],
              services: {
                0x000B: {...type3, ...rest},
              },
            ),
          ),
        );
        final polled = Felica.polled(idm, pmm, Uint16List.fromList([0x12FC]));
        final basic = await engine.handleFelica(
          tag: polled,
          readExtended: false,
        );

        // The first scan reads the NDEF blocks only, and shows the message.
        final card = basic!.card as Felica;
        expect(card.systemCode, [0x88B4]);
        expect(card.dump!.systemCodes, [0x88B4]);
        expect(card.dump!.services[0x000B]!.keys, type3.keys);
        expect(basic.isExtendedInfoFullyLoaded, isFalse);
        expect(ndefOf(card)!.message, message);

        final full = await engine.handleFelica(tag: polled);
        expect(full!.isExtendedInfoFullyLoaded, isTrue);
        expect((full.card as Felica).dump!.services[0x000B]![0x88], rest[0x88]);
        expect(ndefOf(full.card)!.message, message);
      },
    );

    test('a Lite-S without NDEF shows after one batch', () async {
      // Not an Amusement IC, whose check would read S_PAD0 first.
      final lite = _hex('0101010203040506');
      final channel = _FelicaTagChannel(
        FelicaTag(
          idm: lite,
          pmm: pmm,
          systemCodes: const [0x88B4],
          services: {
            0x000B: {...type3, 0: Uint8List(16), ...rest},
          },
        ),
      );
      final basic = await CardReaderEngine(channel).handleFelica(
        tag: Felica(lite, pmm, Uint16List.fromList([0x88B4])),
        readExtended: false,
      );

      expect(channel.commands, [0x06]);
      expect(basic!.isExtendedInfoFullyLoaded, isFalse);
      expect(ndefOf(basic.card), isNull);
    });

    test('a Lite-S holding NDEF also answers 0x12FC and Type A', () {
      final target = emulationTargetFor(lite(), type4MaxRead: 51);
      expect(target.kind, EmulationKind.felica);
      expect(target.type4, isNotNull);

      final tag = target.felica!;
      expect(tag.systemCodes, [0x88B4]);
      expect(tag.activationSystemCode, 0x12FC);
      expect(poll(tag, 0x12FC), [0x01, ...idm, ...pmm, 0x12, 0xFC]);
      expect(poll(tag, 0x88B4), [0x01, ...idm, ...pmm, 0x88, 0xB4]);
      expect(poll(tag, 0xFE00), isNull);
      // The alias is not a system of its own.
      expect(tag.process(Uint8List.fromList([0x0C, ...idm])), [
        0x0D,
        ...idm,
        1,
        0x88,
        0xB4,
      ]);
    });

    test('a Lite-S without NDEF answers 0x88B4 only', () {
      final blocks = {...type3, 0: Uint8List(16)};
      final target = emulationTargetFor(lite(blocks: blocks), type4MaxRead: 51);
      expect(target.type4, isNull);
      expect(target.felica!.activationSystemCode, 0x88B4);
      expect(poll(target.felica!, 0x12FC), isNull);
    });

    test('a Standard card holds NDEF in its 0x12FC system only', () {
      final standardPmm = _hex('0120220427674EFF');
      final card = Felica(
        idm,
        standardPmm,
        Uint16List.fromList([0x0003, 0x12FC]),
        dump: FelicaDump.ofSystems(
          complete: true,
          systems: [
            FelicaSystem(code: 0x0003),
            FelicaSystem(code: 0x12FC, services: {0x000B: type3}),
          ],
        ),
      );
      expect(ndefOf(card)!.message, message);
      final target = emulationTargetFor(card, type4MaxRead: 51);
      expect(target.type4, isNotNull);
      expect(target.felica!.aliasCodes, isEmpty);
      expect(target.felica!.activationSystemCode, 0x0003);

      final elsewhere = Felica(
        idm,
        standardPmm,
        Uint16List.fromList([0x0003]),
        dump: FelicaDump(
          complete: true,
          systemCode: 0x0003,
          services: {0x000B: type3},
        ),
      );
      expect(ndefOf(elsewhere), isNull);
      expect(emulationTargetFor(elsewhere, type4MaxRead: 51).type4, isNull);
    });

    test(
      'the first batch finds NDEF in a system other than the polled one',
      () async {
        final card = Felica(
          idm,
          _hex('0120220427674EFF'),
          Uint16List.fromList([0xFE00, 0x12FC]),
          dump: FelicaDump.ofSystems(
            complete: true,
            systems: [
              FelicaSystem(code: 0xFE00),
              FelicaSystem(code: 0x12FC, services: {0x000B: type3}),
            ],
          ),
        );
        final engine = CardReaderEngine(
          _FelicaTagChannel(emulationTargetFor(card, type4MaxRead: 51).felica!),
        );
        final basic = await engine.handleFelica(
          tag: Felica(idm, card.pmm, Uint16List.fromList([0xFE00])),
          readExtended: false,
        );

        expect((basic!.card as Felica).systemCode, [0xFE00, 0x12FC]);
        expect(ndefOf(basic.card)!.message, message);
        expect(basic.isExtendedInfoFullyLoaded, isFalse);
      },
    );
  });

  test('a card that does not list its systems shows its polled one', () async {
    final history = _hex('1602000033A0E3420000E80300000100');
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003]),
      dump: FelicaDump(
        complete: true,
        systemCode: 0x0003,
        services: {
          0x090F: {0: history},
        },
      ),
    );
    final engine = CardReaderEngine(
      _UnlistedChannel(emulationTargetFor(saved, type4MaxRead: 51).felica!),
    );
    final polled = Felica(idm, saved.pmm, Uint16List.fromList([0x0003]));
    final basic = await engine.handleFelica(tag: polled, readExtended: false);

    expect(basic!.card, isA<Suica>());
    expect((basic.card as Felica).systemCode, [0x0003]);
    // The background read keeps to the polled system, as listed.
    final full = await engine.handleFelica(tag: polled, existingCard: basic);
    expect(full!.isExtendedInfoFullyLoaded, isTrue);
    expect((full.card as Suica).balance, 1000);
  });
}
