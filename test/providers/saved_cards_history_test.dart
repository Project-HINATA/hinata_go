import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/models/card/scan_merge.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _idm = ICCard.hexToBytes('01140E1234567890');
final _pmm = ICCard.hexToBytes('0120220427674EFF');
final _systemCodes = Uint16List.fromList([0x0003]);

Uint8List _block(int value) => Uint8List(16)..fillRange(0, 16, value);

/// A history record whose balance is [balance].
Uint8List _record(int balance) => Uint8List.fromList([
  0x16, 0x01, 0x00, 0x02, 0x33, 0xA0, 0xE3, 0x42, //
  0xE3, 0x38, balance & 0xFF, balance >> 8, 0x00, 0x00, 0x01, 0x00,
]);

Felica _felica(FelicaDump? dump) =>
    Felica(_idm, _pmm, _systemCodes, dump: dump);

void main() {
  group('FelicaDump.overlaidWith', () {
    final earlier = FelicaDump(
      complete: true,
      systemCode: 0x0003,
      services: {
        0x008B: {0: _block(1)},
        0x090F: {0: _block(1), 1: _block(1)},
      },
    );

    test('a complete later scan replaces everything', () {
      final later = FelicaDump(
        complete: true,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _block(2)},
        },
      );
      expect(earlier.overlaidWith(later), same(later));
    });

    test('later services replace earlier ones, which stay in place', () {
      final later = FelicaDump(
        complete: false,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _block(2)},
          0x10CB: {0: _block(2)},
        },
        finishedServices: {0x090F},
      );
      final merged = earlier.overlaidWith(later);

      expect(merged.services.keys, [0x008B, 0x090F, 0x10CB]);
      expect(merged.block(0x008B, 0), _block(1));
      expect(merged.services[0x090F]!.keys, [0]);
      expect(merged.block(0x090F, 0), _block(2));
      // The later scan stopped in 0x10CB, which the earlier one lacked.
      expect(merged.complete, isFalse);
      expect(merged.isServiceComplete(0x090F), isTrue);
      expect(merged.isServiceComplete(0x10CB), isFalse);
    });

    test('a service the later scan was cut off in keeps the earlier copy', () {
      final later = FelicaDump(
        complete: false,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _block(2)},
        },
      );
      final merged = earlier.overlaidWith(later);

      expect(merged.block(0x090F, 0), _block(1));
      expect(merged.services[0x090F]!.keys, [0, 1]);
      expect(merged.complete, isTrue);
    });

    test('systems the later scan did not reach are kept', () {
      final twoSystems = FelicaDump.ofSystems(
        complete: true,
        systems: [
          FelicaSystem(
            code: 0x0003,
            services: {
              0x090F: {0: _block(1)},
            },
          ),
          FelicaSystem(
            code: 0xFE00,
            services: {
              0x1A8B: {0: _block(1)},
            },
          ),
        ],
      );
      final later = FelicaDump(
        complete: false,
        services: {
          0x090F: {0: _block(2)},
        },
        finishedServices: {0x090F},
        systemCode: 0x0003,
      );

      final merged = twoSystems.overlaidWith(later);

      expect(merged.systemCodes, [0x0003, 0xFE00]);
      expect(merged.block(0x090F, 0), _block(2));
      expect(merged.systems[1].services[0x1A8B]![0], _block(1));
      expect(merged.complete, isTrue);
    });

    test('a service neither scan finished takes the later copy', () {
      final partial = FelicaDump(
        complete: false,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _block(1), 1: _block(1)},
        },
      );
      final later = FelicaDump(
        complete: false,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _block(2)},
        },
      );
      expect(partial.overlaidWith(later).block(0x090F, 0), _block(2));
    });
  });

  group('mergeScans', () {
    test('a plain FeliCa card becomes a Suica once its history is read', () {
      final snapshot = DateTime(2026, 11, 2);
      final earlier = _felica(null);
      final later = Suica.fromDump(
        _idm,
        _pmm,
        _systemCodes,
        FelicaDump(
          complete: true,
          systemCode: 0x0003,
          services: {
            0x090F: {0: _record(500)},
          },
        ),
        snapshotTime: snapshot,
      );

      final merged = mergeScans(earlier, later);

      expect(merged, isA<Suica>());
      expect((merged as Suica).balance, 500);
      expect(merged.snapshotTime, snapshot);
    });

    test('the later Suica scan sets the balance and snapshot time', () {
      Suica scan(int balance, DateTime time, {bool complete = true}) =>
          Suica.fromDump(
            _idm,
            _pmm,
            _systemCodes,
            FelicaDump(
              complete: complete,
              systemCode: 0x0003,
              services: {
                0x008B: {0: _block(balance)},
                0x090F: {0: _record(balance)},
              },
              finishedServices: const {0x090F},
            ),
            snapshotTime: time,
          );
      final merged =
          mergeScans(
                scan(100, DateTime(2026, 1, 1)),
                scan(300, DateTime(2026, 2, 1), complete: false),
              )
              as Suica;

      expect(merged.balance, 300);
      expect(merged.snapshotTime, DateTime(2026, 2, 1));
      // 0x008B came only from the earlier scan, which read everything.
      expect(merged.dump!.block(0x008B, 0), _block(100));
    });

    test('a FeliCa card is the same card whatever its kind', () {
      final suica = Suica(
        _idm,
        _pmm,
        _systemCodes,
        balance: 0,
        transactions: const [],
      );
      expect(_felica(null).isSameCard(suica), isTrue);
      // A copy of the IDm alone, on a card with another PMm or first system
      // code, is another card.
      for (final other in [
        Felica(Uint8List(8), _pmm, _systemCodes),
        Felica(_idm, ICCard.hexToBytes('00F1000000014300'), _systemCodes),
        Felica(_idm, _pmm, Uint16List.fromList([0xFE00])),
      ]) {
        expect(_felica(null).isSameCard(other), isFalse);
      }
    });
  });

  group('history', () {
    late ProviderContainer container;
    late SavedCardsNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      notifier = container.read(savedCardsProvider.notifier);
    });

    tearDown(() => container.dispose());

    List<ICCard> historyCards() => [
      for (final saved in container.read(savedCardsProvider))
        if (saved.folderId == SavedCardsNotifier.historyFolderId) saved.card,
    ];

    test('a rescan completes the card it left incomplete', () {
      final partial = FelicaDump(
        complete: false,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _record(100)},
        },
      );
      final first = notifier.recordScan(
        _felica(partial),
        id: 'first',
        source: 'NFC',
      );
      expect(first.before, isNull);

      // The card comes back: its basic read, then its full read.
      final second = notifier.recordScan(
        _felica(null),
        id: 'second',
        source: 'NFC',
      );
      expect(second.id, 'first');
      final full = FelicaDump(
        complete: true,
        systemCode: 0x0003,
        services: {
          0x090F: {0: _record(200), 1: _record(100)},
        },
      );
      notifier.updateScan(
        second.id,
        second.before,
        Suica.fromDump(_idm, _pmm, _systemCodes, full),
      );

      final cards = historyCards();
      expect(cards, hasLength(1));
      final card = cards.single as Suica;
      expect(card.isFullyRead, isTrue);
      expect(card.balance, 200);
      final entry = container.read(savedCardsProvider).single;
      expect(entry.id, 'first');
      // The name followed the card from FeliCa to Suica.
      expect(entry.name, card.name);
    });

    test('a name given to the entry is kept', () {
      final first = notifier.recordScan(
        _felica(null),
        id: 'first',
        source: 'NFC',
      );
      final entry = container.read(savedCardsProvider).single;
      notifier.updateCard(entry.copyWith(name: 'Commute'));

      notifier.recordScan(_felica(null), id: 'second', source: 'NFC');

      final saved = container.read(savedCardsProvider).single;
      expect(saved.id, first.id);
      expect(saved.name, 'Commute');
    });

    test('a rescanned card moves to the end, as the latest scan', () {
      final other = Felica(
        ICCard.hexToBytes('0114AABBCCDDEEFF'),
        _pmm,
        _systemCodes,
      );
      notifier.recordScan(_felica(null), id: 'first', source: 'NFC');
      notifier.recordScan(other, id: 'other', source: 'NFC');
      notifier.recordScan(_felica(null), id: 'again', source: 'HINATA');

      final saved = container.read(savedCardsProvider);
      expect([for (final entry in saved) entry.id], ['other', 'first']);
      expect(saved.last.source, 'HINATA');
    });
  });
}
