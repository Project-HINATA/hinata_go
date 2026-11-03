import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/crypto/spad0.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/core/engine/card_reader_engine.dart';
import 'package:hinata_go/core/engine/felica_dump_reader.dart';
import 'package:hinata_go/core/engine/felica_tag.dart';
import 'package:hinata_go/core/engine/type3_ndef_tag.dart';
import 'package:hinata_go/models/card/aic.dart';
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
        systemCode: 0x0003,
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
    final engine = CardReaderEngine(_FelicaTagChannel(target.felica));

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
      target.felica.process(
        Uint8List.fromList([0x06, ...system1, 1, 0x8B, 0x1A, 1, 0x80, 0]),
      ),
      [0x07, ...system1, 0, 0, 1, ...common],
    );
    expect(
      target.felica.process(
        Uint8List.fromList([0x06, ...idm, 1, 0x8B, 0x1A, 1, 0x80, 0]),
      ),
      [0x07, ...idm, 0x01, 0xA6],
    );

    final decoded = ICCard.fromJson(card.toJson()) as Suica;
    expect(decoded.dump!.systemCodes, [0x0003, 0xFE00]);
    expect(decoded.dump!.systems[1].services[0x1A8B]![0], common);
  });

  test(
    'the system codes show over the first read, which stays a Suica',
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
        _FelicaTagChannel(emulationTargetFor(saved, type4MaxRead: 51).felica),
      );
      final polled = Felica(idm, saved.pmm, Uint16List.fromList([0x0003]));
      final basic = await engine.handleFelica(tag: polled, readExtended: false);
      // The first batch of history already makes it a Suica.
      expect(basic!.card, isA<Suica>());
      expect((basic.card as Felica).systemCode, [0x0003]);

      final progress = <ScannedCard>[];
      await engine.handleFelica(
        tag: polled,
        existingCard: basic,
        onProgress: progress.add,
      );

      // Before the history is read again, the codes already show, and the
      // card is still the Suica the first read found.
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
      emulationTargetFor(saved, type4MaxRead: 51).felica,
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
      emulationTargetFor(saved, type4MaxRead: 51, felicaMaxBlocks: 4).felica,
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
    final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;
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
      final tag = emulationTargetFor(saved, type4MaxRead: 51).felica;
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
        systemCode: 0x88B4,
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
    Felica lite({Map<int, Uint8List>? blocks, int polled = 0x12FC}) => Felica(
      idm,
      pmm,
      Uint16List.fromList([polled]),
      dump: FelicaDump(
        complete: true,
        systemCode: polled,
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
        final polled = Felica(idm, pmm, Uint16List.fromList([0x12FC]));
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

      final tag = target.felica;
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
      final target = emulationTargetFor(
        lite(blocks: blocks, polled: 0x88B4),
        type4MaxRead: 51,
      );
      expect(target.type4, isNull);
      expect(target.felica.activationSystemCode, 0x88B4);
      expect(poll(target.felica, 0x12FC), isNull);
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
      expect(target.felica.aliasCodes, isEmpty);
      expect(target.felica.activationSystemCode, 0x0003);

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
  });
}
