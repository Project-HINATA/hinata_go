import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/transit.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/ui/components/reader/transit_history_card.dart';

void main() {
  testWidgets('Suica history displays date without unavailable time', (
    tester,
  ) async {
    final card = Suica(
      Uint8List(8),
      Uint8List(8),
      Uint16List(1),
      balance: 100,
      transactions: [
        TransitTransaction(
          date: DateTime(2025, 1, 2),
          type: 'Ride',
          amount: 100,
          details: 'Station',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitHistoryCard(card: card)),
      ),
    );
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.text('2025/01/02'), findsOneWidget);
    expect(find.text('2025/01/02 00:00:00'), findsNothing);
  });

  testWidgets('a history not read in full is marked', (tester) async {
    TUnion card({required bool complete}) => TUnion(
      Uint8List(4),
      0x20,
      0x0004,
      cardNumber: '31040000000000',
      balance: 10,
      transactions: [
        TransitTransaction(type: 'Ride', amount: -2, details: 'Bus'),
      ],
      isHistoryComplete: complete,
    );
    Future<void> pump(TransitCard card, {bool showReadState = true}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TransitHistoryCard(
                card: card,
                showReadState: showReadState,
              ),
            ),
          ),
        );

    await pump(card(complete: false));
    expect(find.text(l10n.cardNotFullyRead), findsOneWidget);

    await pump(card(complete: true));
    expect(find.text(l10n.cardNotFullyRead), findsNothing);

    // Not while the history is still being read.
    await pump(card(complete: false), showReadState: false);
    expect(find.text(l10n.cardNotFullyRead), findsNothing);

    // Cards saved before completeness was kept count as read in full.
    final legacy = card(complete: false).toJson()..remove('historyComplete');
    expect(TUnion.fromJson(legacy).isHistoryComplete, isTrue);
    expect(
      TUnion.fromJson(card(complete: false).toJson()).isHistoryComplete,
      isFalse,
    );
  });
}
