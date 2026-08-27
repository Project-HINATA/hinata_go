import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/tunion.dart';

void main() {
  group('CardTag Unit Tests', () {
    test('CardTag equality and constants', () {
      expect(CardTag.tUnion, const CardTag('tunion'));
      expect(CardTag.japanTransit, const CardTag('japan_transit'));
      expect(CardTag.issuer('大连明珠卡'), CardTag.issuer('大连明珠卡'));
      expect(
        CardTag.issuer('大连明珠卡'),
        isNot(CardTag.issuer('上海公共交通卡')),
      );
    });

    test('CardTag localization in EN and ZH', () async {
      final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
      final l10nZh = await AppLocalizations.delegate.load(const Locale('zh'));

      expect(CardTag.tUnion.localizedName(l10nEn), 'China T-Union');
      expect(CardTag.tUnion.localizedName(l10nZh), '交通联合');

      expect(CardTag.japanTransit.localizedName(l10nEn), 'Japan Transit IC');
      expect(CardTag.japanTransit.localizedName(l10nZh), '交通系 IC');

      // Global context-free getter
      L10nHolder.update(l10nZh);
      expect(CardTag.tUnion.label, '交通联合');
      L10nHolder.update(l10nEn);
      expect(CardTag.tUnion.label, 'China T-Union');

      // Card issuers without official English translation retain native name
      expect(CardTag.issuer('大连明珠卡').localizedName(l10nEn), '大连明珠卡');
      expect(CardTag.issuer('大连明珠卡').localizedName(l10nZh), '大连明珠卡');

      expect(CardTag.isoDep.localizedName(l10nEn), 'ISO-DEP');
      expect(CardTag.felica.localizedName(l10nEn), 'FeliCa');
    });

    test('CardTag search matching', () async {
      final l10nZh = await AppLocalizations.delegate.load(const Locale('zh'));
      final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));

      expect(CardTag.tUnion.matchesSearch('tunion'), isTrue);
      expect(CardTag.tUnion.matchesSearch('China', l10nEn), isTrue);
      expect(CardTag.tUnion.matchesSearch('交通', l10nZh), isTrue);
      expect(CardTag.issuer('大连明珠卡').matchesSearch('大连'), isTrue);
      expect(CardTag.issuer('大连明珠卡').matchesSearch('北京'), isFalse);
    });

    test('CardTag deserializes legacy raw string lists gracefully', () {
      final rawLegacyTags = ['大连明珠卡', '交通联合', 'ISO-DEP'];
      final tags = rawLegacyTags.map(CardTag.fromJson).toList();

      expect(tags, [
        CardTag.issuer('大连明珠卡'),
        CardTag.tUnion,
        CardTag.isoDep,
      ]);
    });
  });

  group('Card Tags Model Serialization & Deserialization Tests', () {
    test('TUnion preserves tags across JSON serialization', () {
      final card = TUnion(
        Uint8List.fromList([1, 2, 3, 4]),
        0x20,
        0x0044,
        cardNumber: '31051200019246251520',
        balance: 10.24,
        transactions: [],
        tags: [CardTag.issuer('大连明珠卡'), CardTag.tUnion, CardTag.isoDep],
      );

      final json = card.toJson();
      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<TUnion>());
      expect(decoded.tags, [
        CardTag.issuer('大连明珠卡'),
        CardTag.tUnion,
        CardTag.isoDep,
      ]);
    });

    test('Suica preserves tags across JSON serialization', () {
      final card = Suica(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        Uint8List(8),
        Uint16List.fromList([0x0003]),
        balance: 1000,
        transactions: [],
        tags: const [CardTag.suica, CardTag.japanTransit, CardTag.felica],
      );

      final json = card.toJson();
      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Suica>());
      expect(decoded.tags, const [
        CardTag.suica,
        CardTag.japanTransit,
        CardTag.felica,
      ]);
    });

    test('Aime preserves tags across JSON serialization', () {
      final card = Aime(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        Uint8List(10),
        tags: const [CardTag.aime, CardTag.mifareClassic],
      );

      final json = card.toJson();
      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Aime>());
      expect(decoded.tags, const [CardTag.aime, CardTag.mifareClassic]);
    });

    test('Banapass preserves tags across JSON serialization', () {
      final card = Banapass(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        Uint8List(16),
        null,
        tags: const [CardTag.banapass, CardTag.mifareClassic],
      );

      final json = card.toJson();
      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Banapass>());
      expect(decoded.tags, const [CardTag.banapass, CardTag.mifareClassic]);
    });

    test('Amusement IC (AIC) preserves tags across JSON serialization', () {
      final card = Aic(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        Uint8List(8),
        Uint16List.fromList([0x8157]),
        Uint8List.fromList([
          0x50,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
        ]),
        tags: const [CardTag.amusementIc, CardTag.sega, CardTag.felica],
      );

      final json = card.toJson();
      final decoded = ICCard.fromJson(json);
      expect(decoded, isA<Aic>());
      expect(decoded.tags, const [
        CardTag.amusementIc,
        CardTag.sega,
        CardTag.felica,
      ]);
    });

    test('Generic Iso14443 and Iso15693 preserve tags', () {
      final iso14443 = Iso14443(
        Uint8List.fromList([1, 2, 3, 4]),
        0x08,
        0x0004,
        tags: const [CardTag.mifareClassic, CardTag.iso14443a],
      );
      final json14443 = iso14443.toJson();
      expect(ICCard.fromJson(json14443).tags, const [
        CardTag.mifareClassic,
        CardTag.iso14443a,
      ]);

      final iso15693 = Iso15693(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        tags: const [CardTag.iso15693],
      );
      final json15693 = iso15693.toJson();
      expect(ICCard.fromJson(json15693).tags, const [CardTag.iso15693]);
    });
  });
}
