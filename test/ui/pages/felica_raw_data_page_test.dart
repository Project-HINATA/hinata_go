import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/ui/pages/felica_raw_data_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _pump(WidgetTester tester, Felica card) async {
  L10nHolder.update(lookupAppLocalizations(const Locale('en')));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FelicaRawDataPage(card: card),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final idm = ICCard.hexToBytes('012E0102030405F6');

  testWidgets('shows each service with its blocks', (tester) async {
    final card = Felica(
      idm,
      ICCard.hexToBytes('0120220427674EFF'),
      Uint16List.fromList([0x0003]),
      dump: FelicaDump(
        complete: true,
        services: {
          0x090F: {
            0: ICCard.hexToBytes('00112233445566778899AABBCCDDEEFF'),
            1: Uint8List(16),
          },
        },
      ),
    );

    await _pump(tester, card);

    expect(find.text('Service 090F'), findsOneWidget);
    expect(find.text('2 blocks'), findsOneWidget);
    expect(
      find.text('00 11 22 33 44 55 66 77\n88 99 AA BB CC DD EE FF'),
      findsOneWidget,
    );
    expect(find.text(l10n.rawDataComplete), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('names Lite-S blocks and warns when not fully read', (
    tester,
  ) async {
    final card = Aic.fromAccessCode(
      idm,
      ICCard.hexToBytes('00F1000000014300'),
      Uint16List.fromList([0x88B4]),
      ICCard.hexToBytes('50012345678901234567'),
    );

    await _pump(tester, card);

    expect(find.text('S_PAD0'), findsOneWidget);
    expect(find.text(l10n.cardReadIncomplete), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says when no blocks were saved', (tester) async {
    await _pump(
      tester,
      Felica(idm, Uint8List(8), Uint16List.fromList([0x0003])),
    );

    expect(find.text(l10n.rawDataNoBlocks), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
