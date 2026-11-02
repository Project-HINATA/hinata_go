import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/crypto/spad0.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/core/engine/card_reader_engine.dart';
import 'package:hinata_go/core/engine/felica_dump_reader.dart';
import 'package:hinata_go/core/engine/felica_tag.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

/// Hands length-prefixed FeliCa frames to an emulated card.
class _FelicaTagChannel implements NfcCardChannel {
  final FelicaTag tag;

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
    final response = tag.process(Uint8List.sublistView(data, 1));
    if (response == null) throw StateError('No response');
    return Uint8List.fromList([response.length + 1, ...response]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    final engine = CardReaderEngine(_FelicaTagChannel(target.felica));
    final read = await engine.handleFelica(tag: Felica(idm, pmm, systemCodes));

    final card = read!.card;
    expect(card, isA<Aic>());
    expect((card as Aic).accessCodeString, '50012345678901234567');
    expect(card.id, idm);
    expect(target.felica.takeMarkerRead(), isTrue);
  });

  test('a FeliCa card answers polling with its saved identity', () {
    final felica = Felica(
      idm,
      _hex('0120220427674EFF'),
      Uint16List.fromList([0x0003, 0xFE00]),
    );
    final tag = emulationTargetFor(felica, type4MaxRead: 51).felica;

    expect(tag.process(_hex('0000030100')), [
      0x01,
      ...idm,
      ...felica.pmm,
      0x00,
      0x03,
    ]);
    expect(tag.process(_hex('00FE000100')), [
      0x01,
      ...idm,
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
        services: {
          0x090F: {0: block},
        },
      ),
    );
    final tag = emulationTargetFor(felica, type4MaxRead: 51).felica;
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
        services: {
          0x008B: {0: Uint8List(16)},
          0x090F: {0: history, 1: Uint8List(16)},
        },
      ),
    );
    final target = emulationTargetFor(saved, type4MaxRead: 51);
    final engine = CardReaderEngine(_FelicaTagChannel(target.felica));

    final progress = <ScannedCard>[];
    final read = await engine.handleFelica(
      tag: Felica(idm, saved.pmm, saved.systemCode),
      onProgress: progress.add,
    );

    // The history shows record by record, before the other services are
    // listed and read.
    expect(progress, hasLength(2));
    final first = progress.first.card as Suica;
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

  test('a read that stops early keeps its blocks, marked incomplete', () async {
    final saved = Felica(
      idm,
      _hex('0120220427674EFF'),
      systemCodes,
      dump: FelicaDump(
        complete: true,
        services: {
          0x100B: {for (var i = 0; i < 4; i++) i: Uint8List(16)..[0] = i},
        },
      ),
    );
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;
    // Two service searches, then two block reads before the card leaves.
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
          services: {
            0x090F: {0: history},
            0x108F: {0: Uint8List(16), 1: Uint8List(16)},
          },
        ),
      );
      final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;
      // The history's one block and its end, three service searches, then one
      // block of the next service before the card leaves.
      final channel = _FelicaTagChannel(tag, answers: 6);

      final read = await CardReaderEngine(
        channel,
      ).handleFelica(tag: Felica(idm, saved.pmm, saved.systemCode));

      final card = read!.card as Suica;
      expect(card.isFullyRead, isFalse);
      expect(card.isHistoryComplete, isTrue);
      expect(card.dump!.services[0x108F]!.keys, [0]);
      final decoded = ICCard.fromJson(card.toJson()) as Suica;
      expect(decoded.isHistoryComplete, isTrue);
      expect(decoded.dump!.isServiceComplete(0x108F), isFalse);
    },
  );

  test('a Lite-S reads back only the blocks it saved', () async {
    final saved = Aic.fromAccessCode(idm, pmm, systemCodes, accessCode);
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;

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
        services: {
          0x000B: {0x81: mac, 0x91: macA},
        },
      ),
    );
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;
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
  });
}
