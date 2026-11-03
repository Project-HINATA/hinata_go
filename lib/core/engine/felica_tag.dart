import 'package:flutter/foundation.dart';

import '../../models/card/felica.dart';

/// An emulated FeliCa card answering the commands a reader may send without
/// authentication: polling, system code and service queries, and reads
/// without encryption. Writes are refused, so a reader that writes a
/// challenge, such as to a Lite-S RC block, gets no answer to it.
///
/// Only what was saved is emulated: a service or block that was not saved
/// is answered as one the card does not have.
///
/// Each system answers with its own IDm, [idm] with the system number in the
/// high nibble of its first byte, and commands reach the system their IDm
/// names.
///
/// Commands and responses start with the command code, without the FeliCa
/// length byte.
class FelicaTag {
  /// A Check response is 12 bytes plus 16 per block. Through a HINATA
  /// reader that sends a PN532 frame in one HID report, it must fit in the
  /// 53 bytes `TgResponseToInitiator` can carry with its length byte.
  static const defaultMaxBlocksPerRead = 2;

  /// The most blocks one Check answers; a reader asking for more gets an
  /// error, as from a card that reads fewer at once.
  final int maxBlocksPerRead;

  /// The IDm of system 0.
  final Uint8List idm;
  final Uint8List pmm;

  /// The system codes, by system number. The first one is the system code
  /// of the polling response.
  final List<int> systemCodes;

  /// System codes system 0 also answers polling for, as a Lite-S enabled
  /// for NDEF answers 0x12FC besides 0x88B4. Request System Code does not
  /// list them.
  final List<int> aliasCodes;

  /// By system number, the services readable without encryption, each to
  /// its saved blocks.
  final List<Map<int, Map<int, Uint8List>>> systems;

  /// The block whose read counts as the reader reading the card.
  final int? markerBlock;

  bool _markerRead = false;

  FelicaTag({
    required this.idm,
    required this.pmm,
    required this.systemCodes,
    this.aliasCodes = const [],
    Map<int, Map<int, Uint8List>> services = const {},
    List<Map<int, Map<int, Uint8List>>> otherSystems = const [],
    this.markerBlock,
    this.maxBlocksPerRead = defaultMaxBlocksPerRead,
  }) : systems = [
         services,
         for (var number = 1; number < systemCodes.length; number++)
           number - 1 < otherSystems.length ? otherSystems[number - 1] : {},
       ] {
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
    for (final blocks in systems.expand((system) => system.values)) {
      if (blocks.values.any((block) => block.length != 16)) {
        throw ArgumentError('Blocks must be 16 bytes');
      }
    }
  }

  /// The system code the PN532 answers polling with by itself, before the
  /// host sees a command: an alias when there is one, so a reader looking
  /// for NDEF finds it.
  int get activationSystemCode => aliasCodes.firstOrNull ?? systemCodes.first;

  /// System 0's services.
  Map<int, Map<int, Uint8List>> get services => systems.first;

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
    if (command.length < 9) return null;
    final target = command.sublist(1, 9);
    final system = [
      for (var number = 0; number < systems.length; number++) number,
    ].where((number) => listEquals(target, _idmOf(number))).firstOrNull;
    if (system == null) return null;
    Uint8List response(int code, List<int> body) =>
        Uint8List.fromList([code, ...target, ...body]);
    final services = systems[system];
    return switch (command[0]) {
      0x02 => _requestService(command, services, response),
      0x04 => response(0x05, [0x00]),
      0x06 => _check(command, services, response),
      0x08 => response(0x09, [0x01, 0xA5]),
      0x0A => _searchServiceCode(command, services, response),
      0x0C => response(0x0D, [
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
    final number = [
      for (var i = 0; i < systemCodes.length; i++) i,
    ].where((i) => matches(systemCodes[i])).firstOrNull;
    final alias = number == null ? aliasCodes.where(matches).firstOrNull : null;
    if (number == null && alias == null) return null;
    final code = alias ?? systemCodes[number!];
    return Uint8List.fromList([
      0x01,
      ..._idmOf(number ?? 0),
      ...pmm,
      if (command[3] == 0x01) ...[code >> 8, code & 0xFF],
    ]);
  }

  Uint8List _idmOf(int number) =>
      number == 0 ? idm : Felica.systemIdm(idm, number);

  Uint8List? _requestService(
    Uint8List command,
    Map<int, Map<int, Uint8List>> services,
    _Respond response,
  ) {
    final count = command.length > 9 ? command[9] : 0;
    if (count < 1 || count > 32 || command.length != 10 + 2 * count) {
      return null;
    }
    return response(0x03, [
      count,
      for (var i = 0; i < count; i++)
        ...(services.containsKey(_code(command, 10 + 2 * i))
            ? [0x00, 0x00]
            : [0xFF, 0xFF]),
    ]);
  }

  /// The service at the requested index, or 0xFFFF past the last. The card
  /// has no areas to report.
  Uint8List? _searchServiceCode(
    Uint8List command,
    Map<int, Map<int, Uint8List>> services,
    _Respond response,
  ) {
    if (command.length != 11) return null;
    final index = _code(command, 9);
    final codes = services.keys.toList();
    final code = index < codes.length ? codes[index] : 0xFFFF;
    return response(0x0B, [code & 0xFF, code >> 8]);
  }

  Uint8List _check(
    Uint8List command,
    Map<int, Map<int, Uint8List>> services,
    _Respond response,
  ) {
    Uint8List error(int code) => response(0x07, [0x01, code]);

    if (command.length < 10) return error(0xA1);
    final serviceCount = command[9];
    if (serviceCount < 1 || serviceCount > 16) return error(0xA1);
    var offset = 10 + 2 * serviceCount;
    if (command.length <= offset) return error(0xA1);
    final codes = [
      for (var i = 0; i < serviceCount; i++) _code(command, 10 + 2 * i),
    ];
    if (!codes.every(services.containsKey)) return error(0xA6);
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
      if (block == null) return error(0xA8);
      if (number == markerBlock) markerRead = true;
      data.addAll(block);
    }
    if (offset != command.length) return error(0xA2);
    if (markerRead) _markerRead = true;
    return response(0x07, [0x00, 0x00, count, ...data]);
  }

  static int _code(Uint8List command, int offset) =>
      command[offset] | command[offset + 1] << 8;
}

/// Builds a response with [code] and [body] after the IDm it answers for.
typedef _Respond = Uint8List Function(int code, List<int> body);
