import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
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

  testWidgets('renders card tags as badges in header', (tester) async {
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
                tags: const ['大连明珠卡', '交通联合', 'ISO-DEP'],
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
}
