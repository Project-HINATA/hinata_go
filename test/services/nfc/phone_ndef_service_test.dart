import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/services/nfc/mifare_card_writer.dart';
import 'package:hinata_go/services/nfc/nfc_service.dart';
import 'package:hinata_go/services/nfc/phone_ndef_service.dart';
import 'package:ndef/ndef.dart' as ndef;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_nfc_kit/method');
  var data = <Object?>[];
  var writes = 0;
  var corruptRead = false;
  final card = NdefCard.fromRecords([
    ndef.TextRecord(text: '你好', language: 'zh'),
    ndef.UriRecord.fromString('https://example.org'),
  ]);
  NFCTag tag({
    String type = 'iso18092',
    bool available = true,
    bool writable = true,
    int capacity = 512,
  }) => NFCTag.fromJson({
    'type': type,
    'id': '0123456789ABCDEF',
    'standard': 'FeliCa',
    'ndefAvailable': available,
    'ndefWritable': writable,
    'ndefCapacity': capacity,
  });
  Matcher failure(MifareWriteFailure kind) => throwsA(
    isA<MifareCardWriteException>().having((e) => e.failure, 'failure', kind),
  );
  setUp(() {
    data = [];
    writes = 0;
    corruptRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'writeNDEF') {
            writes++;
            data =
                jsonDecode((call.arguments as Map)['data'] as String) as List;
            return null;
          }
          if (call.method == 'readNDEF') {
            return jsonEncode(corruptRead ? [] : data);
          }
          throw StateError('Unexpected NFC call ${call.method}');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final type in [
    'iso18092',
    'mifare_ultralight',
    'mifare_classic',
    'iso7816',
  ]) {
    test(
      'uses system NDEF read/write for $type and verifies multiple records',
      () async {
        final stages = <MifareWriteStage>[];
        await writePhoneNdef(
          tag(type: type),
          card,
          onStage: stages.add,
          isCancelled: () => false,
        );
        expect(writes, 1);
        final read = await readPhoneNdef(tag(type: type));
        expect(read.message, card.message);
        expect(read.physicalCard, isNotNull);
        expect(read.capacity, 512);
        // A FeliCa card's NDEF is read with its blocks instead.
        if (type != 'iso18092') {
          expect(
            (await handleNfcTag(tag(type: type))).card!.card,
            isA<NdefCard>(),
          );
        }
        expect(stages, [
          MifareWriteStage.checkingPermissions,
          MifareWriteStage.writingData,
          MifareWriteStage.verifying,
        ]);
      },
    );
  }
  test(
    'keeps reported SAK/ATQA and marks unavailable phone fields unknown',
    () async {
      final reported = NFCTag.fromJson({
        'type': 'mifare_classic',
        'id': '01020304',
        'standard': 'ISO 14443A',
        'sak': '08',
        'atqa': '0400',
        'ndefAvailable': true,
        'ndefCapacity': 716,
      });
      final card = await readPhoneNdef(reported);
      final physical = card.physicalCard! as Iso14443;
      expect(physical.sak, 8);
      expect(physical.atqa, 4);
      expect(physical.sakKnown, isTrue);
      expect(physical.atqaKnown, isTrue);
      final missing =
          (await readPhoneNdef(tag(type: 'mifare_classic'))).physicalCard!
              as Iso14443;
      expect(missing.sakKnown, isFalse);
      expect(missing.atqaKnown, isFalse);
      final restored = NdefCard.fromJson(card.toJson());
      expect(restored.physicalCard!.toJson(), physical.toJson());
    },
  );
  test(
    'a scanned tag with an unavailable UID is still physical data',
    () async {
      final tag = NFCTag.fromJson({
        'type': 'unknown',
        'id': 'unknown',
        'standard': 'unknown',
        'ndefAvailable': true,
        'ndefCapacity': 144,
      });
      final read = await readPhoneNdef(tag);
      expect(read.hasPhysicalCard, isTrue);
      expect(read.id, isEmpty);
      expect(read.capacity, 144);
      final restored = NdefCard.fromJson(read.toJson());
      expect(restored.hasPhysicalCard, isTrue);
      expect(restored.id, isEmpty);
      expect(restored.isSameCard(NdefCard.fromRecords([])), isFalse);
    },
  );
  test(
    'rejects read-only, too-small and unformatted targets before native writes',
    () async {
      await expectLater(
        writePhoneNdef(
          tag(writable: false),
          card,
          onStage: (_) {},
          isCancelled: () => false,
        ),
        failure(MifareWriteFailure.permissionDenied),
      );
      await expectLater(
        writePhoneNdef(
          tag(capacity: 1),
          card,
          onStage: (_) {},
          isCancelled: () => false,
        ),
        failure(MifareWriteFailure.capacityExceeded),
      );
      await expectLater(
        writePhoneNdef(
          tag(type: 'mifare_classic', available: false),
          card,
          onStage: (_) {},
          isCancelled: () => false,
        ),
        failure(MifareWriteFailure.unsupportedCard),
      );
      await expectLater(
        writePhoneNdef(tag(), card, onStage: (_) {}, isCancelled: () => true),
        failure(MifareWriteFailure.cancelled),
      );
      expect(writes, 0);
    },
  );
  test(
    'does not report success when system write succeeds but read-back differs',
    () async {
      corruptRead = true;
      await expectLater(
        writePhoneNdef(tag(), card, onStage: (_) {}, isCancelled: () => false),
        failure(MifareWriteFailure.verificationFailed),
      );
    },
  );
}
