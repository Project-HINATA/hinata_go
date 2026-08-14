import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/aime.dart';
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
}
