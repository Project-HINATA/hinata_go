import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/crypto/spad0.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/core/engine/card_reader_engine.dart';
import 'package:hinata_go/core/engine/felica_tag.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

/// Hands length-prefixed FeliCa frames to an emulated card.
class _FelicaTagChannel implements NfcCardChannel {
  final FelicaTag tag;

  _FelicaTagChannel(this.tag);

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
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
    final saved = Aic(idm, pmm, systemCodes, accessCode);
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
    // Nothing was saved beyond the identity, so no block reads.
    expect(
      tag.process(
        Uint8List.fromList([0x06, ...idm, 1, 0x0B, 0x00, 1, 0x80, 0]),
      ),
      [0x07, ...idm, 0x01, 0xA6],
    );
  });

  test('only cards with complete saved data are emulated', () {
    expect(emulationKindOf(NdefCard(_hex('D00000'))), EmulationKind.ndef);
    expect(
      emulationKindOf(Felica(idm, pmm, systemCodes)),
      EmulationKind.felica,
    );
    expect(emulationKindOf(Felica(idm, Uint8List(0), systemCodes)), isNull);
    expect(emulationKindOf(Felica(idm, pmm, Uint16List(0))), isNull);
    expect(emulationKindOf(Aic(idm, pmm, systemCodes, Uint8List(4))), isNull);
    expect(emulationKindOf(Iso14443(_hex('01020304'), 0x08, 0x0004)), isNull);
  });
}
