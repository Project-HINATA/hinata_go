import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/providers/current_scan_session_provider.dart';

TUnion _tUnionWithId(List<int> id) {
  return TUnion(
    Uint8List.fromList(id),
    0x20,
    0x0044,
    cardNumber: '1234567890',
    balance: 0,
    transactions: [],
  );
}

void main() {
  test('deduplicates T-Union scans by card number instead of ISO UID', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(currentScanSessionProvider.notifier);
    final firstScan = ScannedCard(
      card: _tUnionWithId([1, 2, 3, 4, 5, 6, 7]),
      source: 'HINATA',
    );
    final secondScan = ScannedCard(
      card: _tUnionWithId([7, 6, 5, 4, 3, 2, 1]),
      source: 'HINATA',
    );

    final firstResult = notifier.recordScan(
      firstScan,
      presenceMode: ScanPresenceMode.explicitRemoval,
    );
    final firstAcceptedAt = container
        .read(currentScanSessionProvider)
        .lastAcceptedScanAt;
    final secondResult = notifier.recordScan(
      secondScan,
      presenceMode: ScanPresenceMode.explicitRemoval,
    );

    expect(firstResult, ScanRecordResult.accepted);
    expect(secondResult, ScanRecordResult.duplicate);
    expect(
      container.read(currentScanSessionProvider).lastAcceptedScanAt,
      firstAcceptedAt,
    );
    expect(container.read(currentScanSessionProvider).isCardPresent, isTrue);
  });

  test('keeps a card present through transient poll misses', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(currentScanSessionProvider.notifier);
    notifier.recordScan(
      ScannedCard(card: _tUnionWithId([1, 2, 3, 4, 5, 6, 7]), source: 'HINATA'),
      presenceMode: ScanPresenceMode.explicitRemoval,
    );

    expect(notifier.markCardMissing(source: 'HINATA'), isFalse);
    expect(container.read(currentScanSessionProvider).isCardPresent, isTrue);
    expect(notifier.markCardMissing(source: 'HINATA'), isFalse);
    expect(container.read(currentScanSessionProvider).isCardPresent, isTrue);
    expect(notifier.markCardMissing(source: 'HINATA'), isTrue);
    expect(container.read(currentScanSessionProvider).isCardPresent, isFalse);
  });
}
