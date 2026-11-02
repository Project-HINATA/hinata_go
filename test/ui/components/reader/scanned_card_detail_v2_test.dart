import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/ui/components/reader/scanned_card_detail_v2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'portable game data hides chip fields while scanned data keeps them',
    (tester) async {
      final tag = Iso14443(ICCard.hexToBytes('01020304'), 8, 4);
      final code = ICCard.hexToBytes('01234567890123456789');
      for (final physical in [null, tag]) {
        for (final card in <CardData>[
          Aime(code, physicalCard: physical),
          Banapass.fromAccessCode(
            accessCode: '30746056644448171490',
            dualKey: true,
            physicalCard: physical,
          ),
        ]) {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(body: ScannedCardDetailV2(card: card)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Access Code'), findsOneWidget);
          for (final label in ['UID', 'SAK', 'ATQA']) {
            expect(
              find.text(label),
              physical == null ? findsNothing : findsOneWidget,
            );
          }
          expect(find.text('0000 0000'), findsNothing);
          if (physical != null) expect(find.text('0102 0304'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('unusable cards keep their detected card type', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScannedCardDetailV2(
              card: Iso14443(
                Uint8List.fromList(const [1, 2, 3, 4]),
                0x08,
                0x0004,
              ),
              isUsable: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('MIFARE Classic 1K'), findsOneWidget);
    expect(find.text('这张卡无法在游戏中使用。'), findsOneWidget);
    expect(find.text('不可在游戏中使用的卡片'), findsNothing);
  });

  testWidgets('renders card tags as badges in header (zh)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScannedCardDetailV2(
              card: Iso14443(
                Uint8List.fromList(const [1, 2, 3, 4]),
                0x08,
                0x0004,
                tags: [CardTag.issuer('大连明珠卡'), CardTag.tUnion, CardTag.isoDep],
              ),
              title: '我的大连卡',
            ),
          ),
        ),
      ),
    );

    expect(find.text('我的大连卡'), findsOneWidget);
    expect(find.text('大连明珠卡'), findsOneWidget);
    expect(find.text('交通联合'), findsOneWidget);
    expect(find.text('ISO-DEP'), findsOneWidget);
  });

  testWidgets('renders localized card tags and T-Union fields (en)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScannedCardDetailV2(
              card: TUnion(
                Uint8List.fromList(const [1, 2, 3, 4]),
                0x20,
                0x0044,
                cardNumber: '31051200019246251520',
                balance: 10.24,
                transactions: const [],
                cardType: '01',
                expiryDate: '2030-12-31',
                issueDate: '2020-01-01',
                tags: [CardTag.issuer('大连明珠卡'), CardTag.tUnion, CardTag.isoDep],
              ),
              title: 'My Dalian Card',
            ),
          ),
        ),
      ),
    );

    expect(find.text('My Dalian Card'), findsOneWidget);
    // Unofficial English names retain native issuer name
    expect(find.text('大连明珠卡'), findsOneWidget);
    // Standard network badge is localized to China T-Union
    expect(find.text('China T-Union'), findsOneWidget);
    expect(find.text('ISO-DEP'), findsOneWidget);

    // Check localized fields
    expect(find.text('Card Type'), findsOneWidget);
    expect(find.text('Standard Card'), findsOneWidget);
    expect(find.text('Valid Until'), findsOneWidget);
    expect(find.text('2030-12-31'), findsOneWidget);
    expect(find.text('Issue Date'), findsOneWidget);
    expect(find.text('2020-01-01'), findsOneWidget);
  });

  testWidgets('renders IDm and Fake Access Code for Felica cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScannedCardDetailV2(
              card: Felica(
                Uint8List.fromList([
                  0x01,
                  0x2e,
                  0x4a,
                  0x90,
                  0x12,
                  0x34,
                  0x56,
                  0x78,
                ]),
                Uint8List.fromList([
                  0x11,
                  0x22,
                  0x33,
                  0x44,
                  0x55,
                  0x66,
                  0x77,
                  0x88,
                ]),
                Uint16List.fromList([0x88b4]),
              ),
              title: 'My Felica Card',
            ),
          ),
        ),
      ),
    );

    expect(find.text('My Felica Card'), findsOneWidget);
    expect(find.text('IDm'), findsOneWidget);
    expect(find.text('012E 4A90 1234 5678'), findsOneWidget);
    expect(find.text('Fake Access Code'), findsOneWidget);
    expect(find.text('0008 5087 4256 0778 4056'), findsOneWidget);
    expect(find.text('PMm'), findsOneWidget);
    expect(find.text('Codes'), findsOneWidget);
  });
}
