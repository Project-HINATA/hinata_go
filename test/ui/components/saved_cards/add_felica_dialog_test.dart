import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/models/card/card_tag.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/ui/components/saved_cards/add_felica_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });
  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            L10nHolder.update(AppLocalizations.of(context));
            return child!;
          },
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AddFelicaDialog(
                    initialFolderId: 'favorites_folder',
                    onAddFolderRequested: () {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

  testWidgets('saves a FeliCa card that can be emulated', (tester) async {
    await open(tester);
    await tester.enterText(field('Name / Description'), 'Office pass');
    await tester.enterText(field('IDm'), '01 14 B3 A4 1E 2C 5D 6F');
    await tester.enterText(field('PMm'), '100B4B428485D0FF');
    expect(saveButton(tester).onPressed, isNull);
    await tester.enterText(field('System Code'), '0003, FE00');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AddFelicaDialog), findsNothing);
    final saved = container.read(savedCardsProvider).single;
    expect(saved.name, 'Office pass');
    expect(saved.folderId, 'favorites_folder');
    expect(saved.source, 'Direct');
    final card = saved.card as Felica;
    expect(card.idString.toUpperCase(), '0114B3A41E2C5D6F');
    expect(card.pmmString.toUpperCase(), '100B4B428485D0FF');
    expect(card.systemCode, [0x0003, 0xFE00]);
    expect(card.tags, [CardTag.felica]);
    expect(emulationKindOf(card), EmulationKind.felica);
  });

  testWidgets('explains malformed input and keeps save disabled', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('Name / Description'), 'Bad');
    await tester.enterText(field('IDm'), '0114B3');
    await tester.enterText(field('PMm'), '100B4B428485D0FF');
    await tester.enterText(field('System Code'), '0003, 0003');
    await tester.pump();

    expect(find.text('Enter exactly 16 hex digits'), findsOneWidget);
    expect(
      find.text(
        'Each system code needs 4 hex digits; up to 16, without repeats',
      ),
      findsOneWidget,
    );
    expect(saveButton(tester).onPressed, isNull);
  });
}
