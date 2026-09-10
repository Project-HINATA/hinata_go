import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/transit.dart';
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
}
