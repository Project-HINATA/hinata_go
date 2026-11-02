import 'dart:typed_data';

import 'aic.dart';
import 'card.dart';
import 'felica.dart';
import 'suica.dart';

/// The card a history entry holds once [later] is scanned over [earlier],
/// both the same physical card.
///
/// A FeliCa card keeps the blocks of both scans, the later one's services
/// over the earlier one's; its kind follows from the merged blocks, and its
/// snapshot time is the later scan's. Any other card is the later scan.
ICCard mergeScans(ICCard earlier, ICCard later) {
  if (earlier is! Felica || later is! Felica) return later;
  final earlierDump = earlier.dump;
  final laterDump = later.dump;
  final dump = earlierDump == null
      ? laterDump
      : laterDump == null
      ? earlierDump
      : earlierDump.overlaidWith(laterDump);
  if (dump == null) return later;
  // The merged dump has every system either scan found.
  final systemCode = dump.systemCodes.length > later.systemCode.length
      ? Uint16List.fromList(dump.systemCodes)
      : later.systemCode;

  final aic = later is Aic ? later : (earlier is Aic ? earlier : null);
  if (aic != null) {
    return Aic(later.id, later.pmm, systemCode, dump: dump, tags: aic.tags);
  }

  final suica = later is Suica ? later : (earlier is Suica ? earlier : null);
  final history = dump.services[Suica.historyService];
  if (systemCode.contains(0x0003) && history?.isNotEmpty == true) {
    return Suica.fromDump(
      later.id,
      later.pmm,
      systemCode,
      dump,
      snapshotTime: later is Suica ? later.snapshotTime : suica?.snapshotTime,
      tags: suica?.tags ?? later.tags,
    );
  }

  return Felica(later.id, later.pmm, systemCode, tags: later.tags, dump: dump);
}
