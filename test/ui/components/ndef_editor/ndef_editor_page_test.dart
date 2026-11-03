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
import 'package:hinata_go/ui/components/ndef_editor/editor_widgets.dart';
import 'package:hinata_go/ui/components/ndef_editor/ndef_editor_page.dart';
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

  /// The text field labelled [label] in an editor form.
  Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w is EditorTextField &&
          (w.label == label || w.label.startsWith('$label · ')),
    ),
    matching: find.byType(TextField),
  );

  Future<void> openNew(WidgetTester tester, {NdefCard? copyOf}) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => showNdefEditor(
                context,
                initialFolderId: 'favorites_folder',
                copyOf: copyOf,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates a named dataset with two records in the selected folder',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openNew(tester);
      await tester.enterText(find.byType(TextField).first, 'Dataset');
      for (final text in ['first', 'second']) {
        await tester.tap(find.text('Add record'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Text'));
        await tester.pumpAndSettle();
        await tester.enterText(field('Content'), text);
        await tapButton(tester, 'Done');
      }
      expect(find.text('Choose a record type'), findsNothing);
      await tapButton(tester, 'Save');
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

  testWidgets('a phone record edits in its preset form', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = NdefCard.fromRecords([
      ndef.UriRecord.fromString('tel:10086'),
    ]);
    await openNew(tester, copyOf: source);
    expect(find.text('Phone'), findsOneWidget);
    await tester.tap(find.text('tel:10086'));
    await tester.pumpAndSettle();

    final number = field('Phone number');
    expect(tester.widget<TextField>(number).controller!.text, '10086');
    await tester.enterText(number, 'call me');
    await tapButton(tester, 'Done');
    expect(find.text('Invalid format'), findsOneWidget);
    await tester.enterText(number, '+86 10010');
    await tapButton(tester, 'Done');
    await tapButton(tester, 'Save');

    final saved = container.read(savedCardsProvider).single.card as NdefCard;
    expect(ndefRecordUri(saved.records.single).toString(), 'tel:+8610010');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a copy of a card\'s NDEF is saved as a new dataset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = NdefCard(
      NdefCard.fromRecords([
        ndef.TextRecord(text: 'on the card', language: 'en'),
      ]).message,
      physicalCard: Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0, 0x44),
    );
    await openNew(tester, copyOf: source);
    expect(find.text('on the card'), findsOneWidget);
    await tapButton(tester, 'Save');

    final saved = container.read(savedCardsProvider).single;
    final card = saved.card as NdefCard;
    expect(card.message, source.message);
    expect(card.physicalCard, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing with unsaved changes asks first', (tester) async {
    await openNew(tester);
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(container.read(savedCardsProvider), isEmpty);
  });

  testWidgets('a record is deleted from its form', (tester) async {
    final source = NdefCard.fromRecords([
      ndef.TextRecord(text: 'keep', language: 'en'),
      ndef.TextRecord(text: 'drop', language: 'en'),
    ]);
    await openNew(tester, copyOf: source);
    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete record'));
    await tester.pumpAndSettle();
    expect(find.text('drop'), findsNothing);
    await tapButton(tester, 'Save');
    final saved = container.read(savedCardsProvider).single.card as NdefCard;
    expect(saved.records.map(ndefRecordValue), ['keep']);
  });

  testWidgets('an open Wi-Fi network has no password field', (tester) async {
    await openNew(tester);
    await tester.tap(find.text('Add record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(field('Password'), findsOneWidget);
    await tester.enterText(field('Network name (SSID)'), 'Guest');
    await tester.enterText(field('Password'), 'short');
    await tapButton(tester, 'Done');
    expect(
      tester.widget<EditorTextField>(find.byType(EditorTextField).last).error,
      'At least 8 characters',
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(field('Password'), findsNothing);
    await tapButton(tester, 'Done');
    expect(find.text('Guest'), findsNothing);
    expect(find.text('Guest · Open'), findsOneWidget);
  });

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
      await tapButton(tester, 'Save');
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
      await tester.tap(find.text('original').last);
      await tester.pumpAndSettle();
      expect(find.text('Edit record'), findsOneWidget);
      expect(field('Content'), findsOneWidget);
      // The identifier stays editable on the type's own form.
      expect(
        tester
            .widget<TextField>(field('Record ID (hex, optional)'))
            .controller!
            .text,
        '01 02',
      );
      await tester.enterText(field('Content'), 'updated');
      await tapButton(tester, 'Done');
      await tapButton(tester, 'Save');
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
    expect(field('Payload (hex)'), findsOneWidget);
    expect(field('Content'), findsNothing);
    await tapButton(tester, 'Done');
    await tapButton(tester, 'Save');
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
      final done = find.widgetWithText(FilledButton, 'Done').last;
      expect(tester.getRect(done).bottom, lessThanOrEqualTo(544));
      await tester.enterText(field('Content'), 'with keyboard');
      await tester.tap(done);
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
        // Saving an empty dataset points at what is missing.
        await tapButton(tester, l10n.save);
        expect(find.text(l10n.ndefFieldRequired), findsOneWidget);
        expect(find.text(l10n.ndefRecordsMissing), findsOneWidget);
        // Large text pushes the row under the floating button; the list
        // scrolls it clear.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.ndefAddRecord));
        await tester.pumpAndSettle();
        expect(find.text(l10n.ndefChooseKind), findsOneWidget);
        await tester.tap(find.text(l10n.ndefText));
        await tester.pumpAndSettle();
        expect(field(l10n.ndefIdHex), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
