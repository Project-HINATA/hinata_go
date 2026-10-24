import 'package:flutter/foundation.dart';

/// An emulated FeliCa card answering the commands a reader may send without
/// authentication: polling, system code and service queries, and reads
/// without encryption. Writes are refused.
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

  /// Service codes readable without encryption; they all read [blocks].
  final Set<int> services;
  final Map<int, Uint8List> blocks;

  /// The block whose read counts as the reader reading the card.
  final int? markerBlock;

  bool _markerRead = false;

  FelicaTag({
    required this.idm,
    required this.pmm,
    required this.systemCodes,
    this.services = const {},
    this.blocks = const {},
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
    if (blocks.values.any((block) => block.length != 16)) {
      throw ArgumentError('Blocks must be 16 bytes');
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
        ...(services.contains(_code(command, 10 + 2 * i))
            ? [0x00, 0x00]
            : [0xFF, 0xFF]),
    ]);
  }

  Uint8List _check(Uint8List command) {
    Uint8List error(int code) => _response(0x07, [0x01, code]);

    if (command.length < 10) return error(0xA1);
    final serviceCount = command[9];
    if (serviceCount < 1 || serviceCount > 16) return error(0xA1);
    var offset = 10 + 2 * serviceCount;
    if (command.length <= offset) return error(0xA1);
    for (var i = 0; i < serviceCount; i++) {
      if (!services.contains(_code(command, 10 + 2 * i))) return error(0xA6);
    }
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
      final block = blocks[number];
      if (block == null) return error(0xA8);
      if (number == markerBlock) markerRead = true;
      data.addAll(block);
    }
    if (offset != command.length) return error(0xA2);
    if (markerRead) _markerRead = true;
    return _response(0x07, [0x00, 0x00, count, ...data]);
  }

  static int _code(Uint8List command, int offset) =>
      command[offset] | command[offset + 1] << 8;

  Uint8List _response(int code, List<int> body) =>
      Uint8List.fromList([code, ...idm, ...body]);
}
