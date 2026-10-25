import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/saved_card.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/card_writer_provider.dart';
import 'package:hinata_go/providers/current_scan_session_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/ui/components/card_detail/bottom_actions.dart';
import 'package:hinata_go/ui/components/reader/scanned_card_detail_v2.dart';
import 'package:hinata_go/ui/components/reader/ndef_records_card.dart';
import 'package:hinata_go/ui/components/reader/current_scan_result_panel.dart';
import 'package:hinata_go/ui/components/saved_cards/add_card_dialog.dart';
import 'package:hinata_go/ui/components/saved_cards/add_felica_dialog.dart';
import 'package:hinata_go/ui/components/saved_cards/ndef_editor_dialog.dart';
import 'package:hinata_go/ui/pages/card_detail_page.dart';
import 'package:hinata_go/ui/pages/saved_cards_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ndefWriterAvailableProvider.overrideWithValue(true),
        cardWriterAvailableProvider.overrideWithValue(false),
      ],
    );
  });
  tearDown(() => container.dispose());
  Widget app(
    Widget home, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        L10nHolder.update(AppLocalizations.of(context));
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: home,
    ),
  );

  testWidgets(
    'creates a named dataset with two records in the selected folder',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const NdefEditorDialog(
                    initialFolderId: 'favorites_folder',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Dataset');
      for (final text in ['first', 'second']) {
        await tester.tap(find.text('Add record'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Content',
          ),
          text,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = container.read(savedCardsProvider).single;
      expect(saved.name, 'Dataset');
      expect(saved.folderId, 'favorites_folder');
      expect((saved.card as NdefCard).records.map(ndefRecordValue), [
        'first',
        'second',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved NDEF details offer writing on iOS backend and no game send',
    (tester) async {
      final saved = SavedCard(
        id: '1',
        name: 'Dataset',
        folderId: 'favorites_folder',
        card: NdefCard.fromRecords([
          ndef.TextRecord(text: 'hello', language: 'en'),
        ]),
      );
      container.read(savedCardsProvider.notifier).addCard(saved);
      await tester.pumpWidget(app(CardDetailPage(savedCard: saved)));
      await tester.pumpAndSettle();
      final actions = tester.widget<CardDetailBottomActions>(
        find.byType(CardDetailBottomActions),
      );
      expect(actions.onWrite, isNotNull);
      expect(actions.onSend, isNull);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('NDEF'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('NDEF record count'), findsOneWidget);
      expect(find.text('NDEF dataset size'), findsOneWidget);
      expect(find.text('NDEF capacity'), findsNothing);
      expect(find.text('UID'), findsNothing);
      expect(find.text('ID'), findsNothing);
      expect(find.byType(NdefRecordsCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScannedCardDetailV2),
          matching: find.text('hello'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('NDEF dataset'));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsNothing);
      expect(find.text('NDEF record count'), findsOneWidget);
      await tester.tap(find.text('NDEF dataset'));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('nfcWellKnown: T'), findsNothing);
      expect(find.text('Save a copy'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsNothing);
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.style?.fontFamily, isNot('monospace'));
      await tester.tap(find.text('Save a copy'));
      await tester.pumpAndSettle();
      final nameField = tester.widget<TextField>(find.byType(TextField));
      expect(nameField.controller!.text, saved.name);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();
      expect(find.text('Write NDEF tag'), findsOneWidget);
      expect(find.text('Write MIFARE card'), findsNothing);
    },
  );
  testWidgets(
    'scan panel separates physical fields from expanded NDEF records',
    (tester) async {
      final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 8, 4);
      final card = NdefCard(
        NdefCard.fromRecords([
          ndef.TextRecord(text: 'scanned', language: 'en'),
        ]).message,
        physicalCard: tag,
        capacity: 720,
      );
      container
          .read(currentScanSessionProvider.notifier)
          .recordScan(
            ScannedCard(card: card, source: 'HINATA'),
            presenceMode: ScanPresenceMode.explicitRemoval,
          );
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: SingleChildScrollView(child: CurrentScanResultPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NdefRecordsCard), findsOneWidget);
      expect(find.text('scanned'), findsOneWidget);
      expect(find.text('NDEF record count'), findsOneWidget);
      expect(find.text('UID'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScannedCardDetailV2),
          matching: find.text('scanned'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'physical NDEF details keep M1 fields, capacity and metadata when edited',
    (tester) async {
      final physical = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 8, 4);
      final saved = SavedCard(
        id: 'physical',
        name: 'M1 NDEF',
        folderId: 'favorites_folder',
        card: NdefCard(
          NdefCard.fromRecords([
            ndef.TextRecord(text: 'hello', language: 'en'),
          ]).message,
          physicalCard: physical,
          capacity: 720,
        ),
      );
      container.read(savedCardsProvider.notifier).addCard(saved);
      await tester.pumpWidget(app(CardDetailPage(savedCard: saved)));
      await tester.pumpAndSettle();
      for (final label in [
        'UID',
        'SAK',
        'ATQA',
        'NDEF record count',
        'NDEF dataset size',
        'NDEF capacity',
        '720 bytes',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('MIFARE Classic'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit NDEF dataset'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final updated =
          container.read(savedCardsProvider).single.card as NdefCard;
      expect(updated.id, physical.id);
      expect(updated.physicalCard!.toJson(), physical.toJson());
      expect(updated.capacity, 720);
    },
  );

  testWidgets('phone NDEF details omit unavailable SAK and ATQA', (
    tester,
  ) async {
    final physical = Iso14443(
      Uint8List.fromList([1, 2, 3, 4]),
      8,
      4,
      sakKnown: false,
      atqaKnown: false,
    );
    final card = NdefCard(
      NdefCard.fromRecords([
        ndef.TextRecord(text: 'phone', language: 'en'),
      ]).message,
      physicalCard: physical,
    );
    await tester.pumpWidget(app(CardDetailPage(card: card)));
    await tester.pumpAndSettle();
    expect(find.text('UID'), findsOneWidget);
    expect(find.text('SAK'), findsNothing);
    expect(find.text('ATQA'), findsNothing);
    expect(find.text('NDEF capacity'), findsNothing);
    expect(find.text('phone'), findsOneWidget);
  });
  Finder contentField(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> openEditor(WidgetTester tester, SavedCard saved) async {
    container.read(savedCardsProvider.notifier).addCard(saved);
    await tester.pumpWidget(app(CardDetailPage(savedCard: saved)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit NDEF dataset'));
    await tester.pumpAndSettle();
  }

  for (final tnf in [
    ndef.TypeNameFormat.media,
    ndef.TypeNameFormat.nfcExternal,
  ]) {
    testWidgets('edits $tnf as text and preserves record ID', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final record = ndef.NDEFRecord(
        tnf: tnf,
        type: Uint8List.fromList(
          utf8.encode(
            tnf == ndef.TypeNameFormat.media
                ? 'application/json'
                : 'neri.moe:hinata',
          ),
        ),
        payload: Uint8List.fromList(utf8.encode('original')),
        id: Uint8List.fromList([1, 2]),
      );
      final saved = SavedCard(
        id: 'edit',
        name: 'Dataset',
        folderId: 'favorites_folder',
        card: NdefCard.fromRecords([record]),
      );
      await openEditor(tester, saved);
      await tester.tap(find.byType(ListTile).last);
      await tester.pumpAndSettle();
      expect(find.text('Edit record'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(contentField('Content'), findsOneWidget);
      await tester.enterText(contentField('Content'), 'updated');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      final actual =
          (container.read(savedCardsProvider).single.card as NdefCard)
              .records
              .single;
      expect(actual.tnf, record.tnf);
      expect(actual.type, record.type);
      expect(actual.id, record.id);
      expect(utf8.decode(actual.payload!), 'updated');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('binary MIME editing remains lossless in raw form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final record = ndef.NDEFRecord(
      tnf: ndef.TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode('application/octet-stream')),
      payload: Uint8List.fromList([0, 0xff, 1, 0x80]),
    );
    final saved = SavedCard(
      id: 'binary',
      name: 'Binary',
      folderId: 'favorites_folder',
      card: NdefCard.fromRecords([record]),
    );
    await openEditor(tester, saved);
    await tester.tap(find.text('MIME · application/octet-stream').last);
    await tester.pumpAndSettle();
    expect(contentField('Payload (hex)'), findsOneWidget);
    expect(contentField('Content'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(
      (container.read(savedCardsProvider).single.card as NdefCard).message,
      (saved.card as NdefCard).message,
    );
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('record editor remains usable with keyboard at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final saved = SavedCard(
        id: 'keyboard',
        name: 'Dataset',
        folderId: 'favorites_folder',
        card: NdefCard.fromRecords([
          ndef.TextRecord(text: 'hello', language: 'en'),
        ]),
      );
      await openEditor(tester, saved);
      await tester.tap(find.text('hello').last);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save').last;
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(544));
      await tester.enterText(contentField('Content'), 'with keyboard');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('with keyboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('tapping Aime/Banapass adds an access code, long press FeliCa', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SavedCardsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.addAimeBanapass));
    await tester.pumpAndSettle();
    expect(find.byType(AddCardDialog), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    await tester.longPress(find.byTooltip(l10n.addAimeBanapass));
    await tester.pumpAndSettle();
    expect(find.byType(AddFelicaDialog), findsOneWidget);
    expect(find.byType(AddCardDialog), findsNothing);
  });

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'new card actions and editor fit narrow screen with large text in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(const SavedCardsPage(), locale: locale, textScale: 1.5),
        );
        await tester.pumpAndSettle();
        for (final button in find.byType(FloatingActionButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(button.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        final folder = tester.getRect(find.byTooltip(l10n.newFolder));
        final ndef = tester.getRect(find.byTooltip(l10n.ndefCreate));
        final aime = tester.getRect(find.byTooltip(l10n.addAimeBanapass));
        expect(folder.bottom, lessThan(ndef.top));
        expect(ndef.bottom, lessThan(aime.top));
        expect(folder.right, ndef.right);
        expect(ndef.right, aime.right);
        expect(find.text(l10n.ndefCreate), findsOneWidget);
        await tester.tap(find.byTooltip(l10n.ndefCreate));
        await tester.pumpAndSettle();
        expect(find.textContaining('添加文本'), findsNothing);
        expect(find.textContaining('Add text, links'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.save),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text(l10n.ndefAddRecord));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(contentField(l10n.ndefIdHex), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
