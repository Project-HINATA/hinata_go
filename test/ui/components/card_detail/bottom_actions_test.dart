import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/ui/components/card_detail/bottom_actions.dart';

void main() {
  for (final width in [320.0, 600.0]) {
    testWidgets('lays out save, write, and send actions at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CardDetailBottomActions(
              onSave: () {},
              onWrite: () {},
              onSend: () {},
              isSaving: false,
              isWriting: false,
              isSending: false,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final saveX = tester.getCenter(find.byIcon(Icons.folder_special)).dx;
      final writeX = tester.getCenter(find.byIcon(Icons.nfc)).dx;
      final sendX = tester.getCenter(find.byIcon(Icons.send)).dx;
      final saveY = tester.getCenter(find.byIcon(Icons.folder_special)).dy;
      final writeY = tester.getCenter(find.byIcon(Icons.nfc)).dy;
      final sendY = tester.getCenter(find.byIcon(Icons.send)).dy;
      expect(
        find.descendant(
          of: find.byType(CardDetailBottomActions),
          matching: find.byType(Text),
        ),
        findsNWidgets(3),
      );
      expect(saveX, lessThan(writeX));
      if (width < 388) {
        expect(saveY, writeY);
        expect(sendY, greaterThan(writeY));
      } else {
        expect(writeX, lessThan(sendX));
        expect(saveY, sendY);
      }
    });
  }
}
