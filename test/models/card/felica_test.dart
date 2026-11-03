import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/type3_ndef_tag.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/scan_log.dart';

void main() {
  group('Felica Model Tests', () {
    test('computes fakeAccessCode and epass correctly from id (IDm)', () {
      final idm = Uint8List.fromList([
        0x01,
        0x2e,
        0x4a,
        0x90,
        0x12,
        0x34,
        0x56,
        0x78,
      ]);
      final pmm = Uint8List(8);
      final systemCode = Uint16List.fromList([0x88b4]);

      final card = Felica(idm, pmm, systemCode);

      expect(card.fakeAccessCodeString, '00085087425607784056');
      expect(card.fakeAccessCode, card.fakeAccessCodeString);
      expect(card.fakeAccessCode.length, 20);
      // Public builds have no cipher; private builds must match the vector.
      expect(card.epass, anyOf(isNull, 'U3W612SERSTTAB2F'));
    });

    test(
      'does not serialize pure derived fields (fakeAccessCode, epass) into toJson',
      () {
        final idm = Uint8List.fromList([
          0x01,
          0x2e,
          0x4a,
          0x90,
          0x12,
          0x34,
          0x56,
          0x78,
        ]);
        final pmm = Uint8List(8);
        final systemCode = Uint16List.fromList([0x88b4]);

        final card = Felica(idm, pmm, systemCode);
        final json = card.toJson();

        expect(json.containsKey('fakeAccessCode'), isFalse);
        expect(json.containsKey('epass'), isFalse);

        final reconstructed = Felica.fromJson(json);
        expect(reconstructed.fakeAccessCode, '00085087425607784056');
        expect(reconstructed.epass, card.epass);
      },
    );
  });

  group('Iso15693 Model Tests', () {
    test('computes epass without serializing it', () {
      final uid = Uint8List.fromList([
        0xe0,
        0x04,
        0x01,
        0x08,
        0x12,
        0x34,
        0x56,
        0x78,
      ]);
      final card = Iso15693(uid);
      expect(card.epass, anyOf(isNull, 'ZMYA3Z3FKF45SR1B'));

      final json = card.toJson();
      expect(json.containsKey('epass'), isFalse);

      final reconstructed = Iso15693.fromJson(json);
      expect(reconstructed.epass, card.epass);
    });
  });

  group('ScanLog Model Tests', () {
    test('derives showValue dynamically and does not persist it in toJson', () {
      final idm = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final card = Felica(idm, Uint8List(8), Uint16List.fromList([0x88b4]));
      final log = ScanLog(
        id: 'test-log-1',
        source: 'NFC',
        card: card,
        timestamp: DateTime(2026, 1, 1),
      );

      expect(log.showValue, card.showedValue);

      final json = log.toJson();
      expect(json.containsKey('showValue'), isFalse);

      final reconstructed = ScanLog.fromJson(json);
      expect(reconstructed.showValue, card.showedValue);
    });

    test('supports legacy ScanLog json with showValue', () {
      final json = {
        'id': 'legacy-log',
        'source': 'NFC',
        'showValue': 'OLD_VALUE',
        'apiType': 'felica',
        'value': '0102030405060708',
        'timestamp': '2026-01-01T00:00:00.000',
      };

      final log = ScanLog.fromJson(json);
      expect(log.id, 'legacy-log');
      expect(log.showValue, 'OLD_VALUE');
    });
  });

  group('NDEF in a FeliCa card', () {
    final idm = Uint8List.fromList([1, 0x2e, 1, 2, 3, 4, 5, 6]);
    final litePmm = Uint8List.fromList([0, 0xF1, 0, 0, 0, 1, 0x43, 0]);
    final message = Uint8List.fromList(
      List.generate(40, (i) => i == 0 ? 0xD1 : i),
    );
    final type3 = Type3NdefTag(message, idm: idm).services[0x000B]!;
    Felica lite(Map<int, Uint8List> blocks, {Uint8List? pmm}) => Felica(
      idm,
      pmm ?? litePmm,
      Uint16List.fromList([0x88B4]),
      dump: FelicaDump(
        complete: true,
        systemCode: 0x88B4,
        services: {0x000B: blocks},
      ),
    );

    test('reads the message after the attribute block', () {
      expect(lite(type3).ndefMessage, message);
    });

    test('a FeliCa Link in Lite-S mode is a Lite', () {
      final linkPmm = Uint8List.fromList(litePmm)..[1] = 0xF2;
      expect(lite(type3, pmm: linkPmm).isLite, isTrue);
      expect(lite(type3, pmm: linkPmm).ndefMessage, message);
    });

    test('a bad checksum or a missing block is no message', () {
      final attribute = Uint8List.fromList(type3[0]!)..[15] ^= 1;
      expect(lite({...type3, 0: attribute}).ndefMessage, isNull);
      expect(lite({...type3}..remove(2)).ndefMessage, isNull);
    });

    test('a Lite-S with NDEF off in its MC block is no message', () {
      final mc = Uint8List(16)..[3] = 0x01;
      expect(lite({...type3, 0x88: mc}).ndefMessage, message);
      expect(lite({...type3, 0x88: Uint8List(16)}).ndefMessage, isNull);
    });
  });
}
