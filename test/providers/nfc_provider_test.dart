import 'dart:typed_data';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/current_scan_session_provider.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'external scan is recorded and saved exactly once while present',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      final scannedCard = ScannedCard(
        card: Aime(
          Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
          0x08,
          0x0004,
          Uint8List.fromList(List<int>.generate(10, (index) => index)),
        ),
        source: 'HINATA',
      );
      final notifier = container.read(nfcProvider.notifier);

      final firstResult = await notifier.handleExternalScan(
        scannedCard,
        presenceMode: ScanPresenceMode.explicitRemoval,
      );
      final duplicateResult = await notifier.handleExternalScan(
        scannedCard,
        presenceMode: ScanPresenceMode.explicitRemoval,
      );

      expect(firstResult, ScanRecordResult.accepted);
      expect(duplicateResult, ScanRecordResult.duplicate);
      expect(container.read(scanLogsProvider), hasLength(1));
      expect(container.read(savedCardsProvider), hasLength(1));
      expect(
        container.read(savedCardsProvider).single.folderId,
        'history_folder',
      );
    },
  );

  group('shouldAttemptFelicaRetry', () {
    test('triggers on confirmed unsupported plain Iso14443 card', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(nfcProvider.notifier);

      final rawTag = NFCTag(
        NFCTagType.iso7816,
        '01020304',
        'ISO 14443-4 (Type A)',
        null,
        '20',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );

      final result = CardReadResult.confirmedUnsupported(
        ScannedCard(
          card: Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x20, 0x0400),
          source: 'NFC',
          isUsable: false,
        ),
      );

      expect(notifier.shouldAttemptFelicaRetry(rawTag, result), isTrue);
    });

    test('triggers on incomplete read for ISO7816 / CPU card candidate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(nfcProvider.notifier);

      final rawIso7816Tag = NFCTag(
        NFCTagType.iso7816,
        '01020304',
        'ISO 14443-4 (Type A)',
        null,
        '20',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );

      expect(
        notifier.shouldAttemptFelicaRetry(
          rawIso7816Tag,
          const CardReadResult.incomplete(),
        ),
        isTrue,
      );
    });

    test('does not trigger on incomplete read for plain Mifare Classic tag', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(nfcProvider.notifier);

      final rawMifareTag = NFCTag(
        NFCTagType.mifare_classic,
        '01020304',
        'ISO 14443-3 (Type A)',
        '0400',
        '08',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );

      expect(
        notifier.shouldAttemptFelicaRetry(
          rawMifareTag,
          const CardReadResult.incomplete(),
        ),
        isFalse,
      );
    });

    test('does not trigger when card is recognized', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(nfcProvider.notifier);

      final rawTag = NFCTag(
        NFCTagType.iso18092,
        '012E000000000000',
        'ISO 18092 (FeliCa)',
        null,
        null,
        null,
        null,
        null,
        null,
        '03004B024F4993FF',
        '0003',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      );

      final recognizedCard = ScannedCard(
        card: Aime(
          Uint8List.fromList([1, 2, 3, 4]),
          0x08,
          0x0004,
          Uint8List.fromList(List<int>.generate(10, (i) => i)),
        ),
        source: 'NFC',
      );

      expect(
        notifier.shouldAttemptFelicaRetry(
          rawTag,
          CardReadResult.recognized(recognizedCard),
        ),
        isFalse,
      );
    });
  });
}
