import 'package:flutter/foundation.dart';

import '../../models/card/felica_dump.dart';

/// An emulated FeliCa card answering the commands a reader may send without
/// authentication: polling, system code and service queries, and reads
/// without encryption. Writes are refused, so a reader that writes a
/// challenge, such as to a Lite-S RC block, gets no answer to it.
///
/// A block the card has but whose data was not saved reads as zeros.
///
/// Commands and responses start with the command code, without the FeliCa
/// length byte.
class FelicaTag {
  /// A Check response is 12 bytes plus 16 per block, and must fit in the
  /// 53 bytes `TgResponseToInitiator` can carry with its length byte over HID.
  static const maxBlocksPerRead = 2;

  final Uint8List idm;
  final Uint8List pmm;

  /// The first one is the system code of the polling response.
  final List<int> systemCodes;

  /// Service codes readable without encryption, each to its saved blocks.
  final Map<int, Map<int, Uint8List>> services;

  /// Whether the card's blocks were not all saved. Then any service that
  /// reads without encryption is answered, and every block missing from it
  /// reads as zeros; otherwise a block past the saved ones is past the end of
  /// its service.
  final bool partial;

  /// Block numbers every service has though they may not be saved, such as
  /// the fixed Lite-S blocks; missing ones read as zeros.
  final Set<int> fixedBlocks;

  /// The block whose read counts as the reader reading the card.
  final int? markerBlock;

  bool _markerRead = false;

  FelicaTag({
    required this.idm,
    required this.pmm,
    required this.systemCodes,
    this.services = const {},
    this.partial = false,
    this.fixedBlocks = const {},
    this.markerBlock,
  }) {
    if (idm.length != 8 || pmm.length != 8) {
      throw ArgumentError('IDm and PMm must be 8 bytes');
    }
    if (systemCodes.isEmpty) {
      throw ArgumentError.value(
        systemCodes,
        'systemCodes',
        'Must not be empty',
      );
    }
    for (final blocks in services.values) {
      if (blocks.values.any((block) => block.length != 16)) {
        throw ArgumentError('Blocks must be 16 bytes');
      }
    }
  }

  /// Whether [markerBlock] was read since the previous call.
  bool takeMarkerRead() {
    final read = _markerRead;
    _markerRead = false;
    return read;
  }

  /// Returns the response to [command], or null when a card stays silent.
  Uint8List? process(Uint8List command) {
    if (command.isEmpty) return null;
    if (command[0] == 0x00) return _poll(command);
    if (command.length < 9 || !listEquals(command.sublist(1, 9), idm)) {
      return null;
    }
    return switch (command[0]) {
      0x02 => _requestService(command),
      0x04 => _response(0x05, [0x00]),
      0x06 => _check(command),
      0x08 => _response(0x09, [0x01, 0xA5]),
      0x0A => _searchServiceCode(command),
      0x0C => _response(0x0D, [
        systemCodes.length,
        for (final code in systemCodes) ...[code >> 8, code & 0xFF],
      ]),
      _ => null,
    };
  }

  Uint8List? _poll(Uint8List command) {
    if (command.length != 5) return null;
    // 0xFF in either byte of the requested system code matches anything.
    bool matches(int code) =>
        (command[1] == 0xFF || command[1] == code >> 8) &&
        (command[2] == 0xFF || command[2] == code & 0xFF);
    final code = systemCodes.where(matches).firstOrNull;
    if (code == null) return null;
    return Uint8List.fromList([
      0x01,
      ...idm,
      ...pmm,
      if (command[3] == 0x01) ...[code >> 8, code & 0xFF],
    ]);
  }

  Uint8List? _requestService(Uint8List command) {
    final count = command.length > 9 ? command[9] : 0;
    if (count < 1 || count > 32 || command.length != 10 + 2 * count) {
      return null;
    }
    return _response(0x03, [
      count,
      for (var i = 0; i < count; i++)
        ...(_hasService(_code(command, 10 + 2 * i))
            ? [0x00, 0x00]
            : [0xFF, 0xFF]),
    ]);
  }

  /// The service at the requested index, or 0xFFFF past the last. The card
  /// has no areas to report.
  Uint8List? _searchServiceCode(Uint8List command) {
    if (command.length != 11) return null;
    final index = _code(command, 9);
    final codes = services.keys.toList();
    final code = index < codes.length ? codes[index] : 0xFFFF;
    return _response(0x0B, [code & 0xFF, code >> 8]);
  }

  Uint8List _check(Uint8List command) {
    Uint8List error(int code) => _response(0x07, [0x01, code]);

    if (command.length < 10) return error(0xA1);
    final serviceCount = command[9];
    if (serviceCount < 1 || serviceCount > 16) return error(0xA1);
    var offset = 10 + 2 * serviceCount;
    if (command.length <= offset) return error(0xA1);
    final codes = [
      for (var i = 0; i < serviceCount; i++) _code(command, 10 + 2 * i),
    ];
    if (!codes.every(_hasService)) return error(0xA6);
    final count = command[offset++];
    if (count < 1 || count > maxBlocksPerRead) return error(0xA2);

    final data = <int>[];
    var markerRead = false;
    for (var i = 0; i < count; i++) {
      if (offset >= command.length) return error(0xA2);
      final head = command[offset];
      if (head & 0x0F >= serviceCount) return error(0xA3);
      if (head & 0x70 != 0) return error(0xA7);
      int number;
      if (head & 0x80 != 0) {
        if (offset + 2 > command.length) return error(0xA2);
        number = command[offset + 1];
        offset += 2;
      } else {
        if (offset + 3 > command.length) return error(0xA2);
        number = command[offset + 1] | command[offset + 2] << 8;
        offset += 3;
      }
      final block = services[codes[head & 0x0F]]?[number];
      if (block == null && !partial && !fixedBlocks.contains(number)) {
        return error(0xA8);
      }
      if (number == markerBlock) markerRead = true;
      data.addAll(block ?? Uint8List(16));
    }
    if (offset != command.length) return error(0xA2);
    if (markerRead) _markerRead = true;
    return _response(0x07, [0x00, 0x00, count, ...data]);
  }

  bool _hasService(int code) =>
      services.containsKey(code) ||
      (partial && FelicaDump.readsWithoutEncryption(code));

  static int _code(Uint8List command, int offset) =>
      command[offset] | command[offset + 1] << 8;

  Uint8List _response(int code, List<int> body) =>
      Uint8List.fromList([code, ...idm, ...body]);
}
