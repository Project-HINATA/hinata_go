import 'dart:math';

import 'package:flutter/foundation.dart';

/// A read-only NFC Forum Type 3 tag (FeliCa) serving one NDEF message.
///
/// Commands and responses start with the command code, without the FeliCa
/// length byte.
class Type3NdefTag {
  static const ndefSystemCode = 0x12FC;

  /// Every timing byte at its maximum, as Android HCE-F does, so readers wait
  /// out the round trip through the host.
  static final defaultPmm = Uint8List.fromList(List.filled(8, 0xFF));

  /// A Check response is 12 bytes plus 16 per block, and must fit in the
  /// 53 bytes `TgResponseToInitiator` can carry with its length byte over HID.
  static const maxBlocksPerRead = 2;

  static const _readOnlyService = 0x000B;
  static const _readWriteService = 0x0009;

  final Uint8List idm;
  final Uint8List pmm;
  final Uint8List _blocks;
  final int _dataBlocks;

  bool _messageRead = false;

  Type3NdefTag(Uint8List message, {required this.idm, Uint8List? pmm})
    : pmm = pmm ?? defaultPmm,
      _dataBlocks = (message.length + 15) ~/ 16,
      _blocks = Uint8List(16 + (message.length + 15) ~/ 16 * 16) {
    if (idm.length != 8 || this.pmm.length != 8) {
      throw ArgumentError('IDm and PMm must be 8 bytes');
    }
    if (message.isEmpty || _dataBlocks > 0xFFFF) {
      throw ArgumentError.value(message.length, 'message.length');
    }
    final attribute = [
      0x10, // mapping version 1.0
      maxBlocksPerRead, // Nbr
      0x01, // Nbw
      _dataBlocks >> 8, _dataBlocks & 0xFF, // Nmaxb
      0x00, 0x00, 0x00, 0x00,
      0x00, // WriteF: no write in progress
      0x00, // RWFlag: read-only
      message.length >> 16, (message.length >> 8) & 0xFF, message.length & 0xFF,
    ];
    final checksum = attribute.fold<int>(0, (sum, b) => sum + b);
    _blocks
      ..setAll(0, attribute)
      ..setAll(14, [(checksum >> 8) & 0xFF, checksum & 0xFF])
      ..setAll(16, message);
  }

  static const _systemCode = [ndefSystemCode >> 8, ndefSystemCode & 0xFF];

  /// Whether the last data block was read since the previous call.
  bool takeMessageRead() {
    final read = _messageRead;
    _messageRead = false;
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
      0x0C => _response(0x0D, [0x01, ..._systemCode]),
      _ => null,
    };
  }

  Uint8List? _poll(Uint8List command) {
    if (command.length != 5) return null;
    // 0xFF in either byte of the requested system code matches anything.
    final high = command[1] == 0xFF || command[1] == ndefSystemCode >> 8;
    final low = command[2] == 0xFF || command[2] == ndefSystemCode & 0xFF;
    if (!high || !low) return null;
    return Uint8List.fromList([
      0x01,
      ...idm,
      ...pmm,
      if (command[3] == 0x01) ..._systemCode,
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
        ...(_isNdefService(command, 10 + 2 * i) ? [0, 0] : [0xFF, 0xFF]),
    ]);
  }

  Uint8List _check(Uint8List command) {
    Uint8List error(int code) => _response(0x07, [0x01, code]);

    if (command.length < 10) return error(0xA1);
    final services = command[9];
    if (services < 1 || services > 16) return error(0xA1);
    var offset = 10 + 2 * services;
    if (command.length <= offset) return error(0xA1);
    for (var i = 0; i < services; i++) {
      if (!_isNdefService(command, 10 + 2 * i)) return error(0xA6);
    }
    final count = command[offset++];
    if (count < 1 || count > maxBlocksPerRead) return error(0xA2);

    final data = <int>[];
    for (var i = 0; i < count; i++) {
      if (offset >= command.length) return error(0xA2);
      final head = command[offset];
      if (head & 0x0F >= services) return error(0xA3);
      if (head & 0x70 != 0) return error(0xA7);
      int block;
      if (head & 0x80 != 0) {
        if (offset + 2 > command.length) return error(0xA2);
        block = command[offset + 1];
        offset += 2;
      } else {
        if (offset + 3 > command.length) return error(0xA2);
        block = command[offset + 1] | command[offset + 2] << 8;
        offset += 3;
      }
      if (block > _dataBlocks) return error(0xA8);
      if (block == _dataBlocks) _messageRead = true;
      data.addAll(_blocks.sublist(block * 16, block * 16 + 16));
    }
    if (offset != command.length) return error(0xA2);
    return _response(0x07, [0x00, 0x00, count, ...data]);
  }

  bool _isNdefService(Uint8List command, int offset) {
    final code = command[offset] | command[offset + 1] << 8;
    return code == _readOnlyService || code == _readWriteService;
  }

  Uint8List _response(int code, List<int> body) =>
      Uint8List.fromList([code, ...idm, ...body]);

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
