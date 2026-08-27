import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/tunion.dart';

void main() {
  group('Card Tags Serialization & Deserialization Tests', () {
    test('TUnion preserves tags across JSON serialization', () {
      final card = TUnion(
        Uint8List.fromList([1, 2, 3, 4]),
        0x20,
        0x0044,
        cardNumber: '31051200019246251520',
        balance: 10.24,
        transactions: [],
        tags: const ['大连明珠卡', '交通联合', 'ISO-DEP'],
      );

      final json = card.toJson();
      expect(json['tags'], ['大连明珠卡', '交通联合', 'ISO-DEP']);

      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<TUnion>());
      expect(decoded.tags, ['大连明珠卡', '交通联合', 'ISO-DEP']);
    });

    test('Suica preserves tags across JSON serialization', () {
      final card = Suica(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        Uint8List(8),
        Uint16List.fromList([0x0003]),
        balance: 1000,
        transactions: [],
        tags: const ['Suica', '交通系 IC', 'FeliCa'],
      );

      final json = card.toJson();
      expect(json['tags'], ['Suica', '交通系 IC', 'FeliCa']);

      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Suica>());
      expect(decoded.tags, ['Suica', '交通系 IC', 'FeliCa']);
    });

    test('Aime preserves tags across JSON serialization', () {
      final card = Aime(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        Uint8List(10),
        tags: const ['Aime', 'MIFARE Classic'],
      );

      final json = card.toJson();
      expect(json['tags'], ['Aime', 'MIFARE Classic']);

      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Aime>());
      expect(decoded.tags, ['Aime', 'MIFARE Classic']);
    });

    test('Banapass preserves tags across JSON serialization', () {
      final card = Banapass(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        Uint8List(16),
        null,
        tags: const ['Banapass', 'MIFARE Classic'],
      );

      final json = card.toJson();
      expect(json['tags'], ['Banapass', 'MIFARE Classic']);

      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Banapass>());
      expect(decoded.tags, ['Banapass', 'MIFARE Classic']);
    });

    test('Amusement IC (AIC) preserves tags across JSON serialization', () {
      final card = Aic(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        Uint8List(8),
        Uint16List.fromList([0x8157]),
        Uint8List.fromList([0x50, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]),
        tags: const ['Amusement IC', 'SEGA', 'FeliCa'],
      );

      final json = card.toJson();
      expect(json['tags'], ['Amusement IC', 'SEGA', 'FeliCa']);

      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Aic>());
      expect(decoded.tags, ['Amusement IC', 'SEGA', 'FeliCa']);
    });

    test('Generic Iso14443 and Iso15693 preserve tags', () {
      final iso14443 = Iso14443(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        tags: const ['MIFARE Classic', 'ISO 14443 Type A'],
      );
      final json14443 = iso14443.toJson();
      expect(ICCard.fromJson(json14443).tags, ['MIFARE Classic', 'ISO 14443 Type A']);

      final iso15693 = Iso15693(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        tags: const ['ISO 15693'],
      );
      final json15693 = iso15693.toJson();
      expect(ICCard.fromJson(json15693).tags, ['ISO 15693']);
    });
  });
}
