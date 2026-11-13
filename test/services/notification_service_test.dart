import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/services/notification_service.dart';

void main() {
  testWidgets(
    'top toast does not block taps on top bar buttons while visible',
    (tester) async {
      final service = NotificationService();
      var leftTapped = false;
      var rightTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            return Overlay(
              key: service.overlayKey,
              initialEntries: [
                OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
              ],
            );
          },
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      key: const Key('top_left_button'),
                      icon: const Icon(Icons.close),
                      onPressed: () => leftTapped = true,
                    ),
                    IconButton(
                      key: const Key('top_right_button'),
                      icon: const Icon(Icons.check),
                      onPressed: () => rightTapped = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      service.showInfo('Saved');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.byKey(const Key('top_left_button')));
      await tester.tap(find.byKey(const Key('top_right_button')));
      expect(leftTapped, isTrue);
      expect(rightTapped, isTrue);

      // Advance past the 3s toast timer and reverse animation so no pending
      // timers remain when the test ends.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}
