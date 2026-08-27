import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/ui/components/reader/scanned_card_detail_v2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
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
                tags: [
                  CardTag.issuer('大连明珠卡'),
                  CardTag.tUnion,
                  CardTag.isoDep,
                ],
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

  testWidgets('renders localized card tags and T-Union fields (en)', (tester) async {
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
                tags: [
                  CardTag.issuer('大连明珠卡'),
                  CardTag.tUnion,
                  CardTag.isoDep,
                ],
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
}
