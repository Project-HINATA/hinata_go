import 'dart:math';

import 'package:flutter/foundation.dart';

import 'felica_tag.dart';

/// A read-only NFC Forum Type 3 tag serving one NDEF message.
class Type3NdefTag extends FelicaTag {
  static const ndefSystemCode = 0x12FC;

  /// Every timing byte at its maximum, as Android HCE-F does, so readers wait
  /// out the round trip through the host.
  static final defaultPmm = Uint8List.fromList(List.filled(8, 0xFF));

  static const _readOnlyService = 0x000B;
  static const _readWriteService = 0x0009;

  Type3NdefTag._(
    int dataBlocks,
    Uint8List message,
    Uint8List idm,
    Uint8List pmm,
  ) : super(
        idm: idm,
        pmm: pmm,
        systemCodes: const [ndefSystemCode],
        services: const {_readOnlyService, _readWriteService},
        blocks: _blocksFor(message, dataBlocks),
        markerBlock: dataBlocks,
      );

  factory Type3NdefTag(
    Uint8List message, {
    required Uint8List idm,
    Uint8List? pmm,
  }) {
    final dataBlocks = (message.length + 15) ~/ 16;
    if (message.isEmpty || dataBlocks > 0xFFFF) {
      throw ArgumentError.value(message.length, 'message.length');
    }
    return Type3NdefTag._(dataBlocks, message, idm, pmm ?? defaultPmm);
  }

  /// Whether the last data block was read since the previous call.
  bool takeMessageRead() => takeMarkerRead();

  static Map<int, Uint8List> _blocksFor(Uint8List message, int dataBlocks) {
    final attribute = Uint8List(16)
      ..setAll(0, [
        0x10, // mapping version 1.0
        FelicaTag.maxBlocksPerRead, // Nbr
        0x01, // Nbw
        dataBlocks >> 8, dataBlocks & 0xFF, // Nmaxb
        0x00, 0x00, 0x00, 0x00,
        0x00, // WriteF: no write in progress
        0x00, // RWFlag: read-only
        message.length >> 16,
        (message.length >> 8) & 0xFF,
        message.length & 0xFF,
      ]);
    final checksum = attribute.take(14).fold<int>(0, (sum, b) => sum + b);
    attribute.setAll(14, [(checksum >> 8) & 0xFF, checksum & 0xFF]);

    final padded = Uint8List(dataBlocks * 16)..setAll(0, message);
    return {
      0: attribute,
      for (var i = 0; i < dataBlocks; i++)
        i + 1: Uint8List.sublistView(padded, i * 16, i * 16 + 16),
    };
  }

  /// An NFCID2 for a Type 3 tag rather than an NFC-DEP target: `02 FE`, then
  /// random bytes.
  static Uint8List randomIdm([Random? random]) {
    final source = random ?? Random.secure();
    return Uint8List.fromList([
      0x02,
      0xFE,
      for (var i = 0; i < 6; i++) source.nextInt(256),
    ]);
  }
}
