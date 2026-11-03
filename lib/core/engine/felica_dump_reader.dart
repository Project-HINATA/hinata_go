import 'dart:developer';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../models/card/felica.dart';
import '../../models/card/felica_dump.dart';
import '../../models/card/suica.dart';

/// Reads every block of a FeliCa card that reads without encryption.
///
/// Frames carry the FeliCa length byte, as [NfcCardChannel.transceive]
/// expects.
class FelicaDumpReader {
  /// The Lite and Lite-S service that reads every block.
  static const liteService = 0x000B;

  /// The Lite-S blocks, by address: S_PAD0–13, REG, RC, MAC, ID, D_ID,
  /// SER_C, SYS_C, CKV, CK, MC, WCNT, MAC_A, STATE and CRC_CHECK. A Lite
  /// lacks some of them, which then just fail to read.
  static const liteBlocks = [
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, //
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, //
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, //
    0x90, 0x91, 0x92, 0xA0,
  ];

  /// Bounds on a card that never reports the end of its services or blocks.
  static const _maxServiceIndex = 0x400;
  static const _maxBlocksPerService = 0x1000;

  final NfcCardChannel channel;

  /// How many blocks one Read Without Encryption asks for at first, as many
  /// as [channel] passes back. A card that reads fewer at once halves it.
  final int blocksPerRead;

  /// How many blocks a read asks for now.
  late int _batchSize = blocksPerRead;

  FelicaDumpReader(this.channel, {this.blocksPerRead = 2});

  /// After a batch failed whole: when its blocks each read alone, the card
  /// refused how many were asked for, not one of them, so ask for fewer.
  void _fitBatch(int asked, int readAlone) {
    if (asked > 1 && readAlone == asked) _batchSize = asked ~/ 2;
  }

  /// Reads [tag]'s blocks, in each of its systems. Never throws: if the card
  /// stops answering, the blocks read so far come back in a dump that is not
  /// complete.
  ///
  /// The card's systems are listed first, unless [systemCodes] gives them,
  /// as the first batch listed them; then the services in [first] are
  /// read in the polled system before the rest. [onProgress] gets the dump
  /// once the systems are known and after each block of [first], so the
  /// system codes and what a card is mostly read for show as they are read.
  /// The finished dump keeps the card's order of systems and services.
  Future<FelicaDump> read(
    Felica tag, {
    List<int> first = const [],
    List<int>? systemCodes,
    void Function(FelicaDump dump)? onProgress,
  }) async {
    final polledCode = tag.systemCode.firstOrNull ?? 0;
    final polled = tag.id[0] >> 4;
    // By system number; until the systems are listed, only the polled one.
    var codes = <int>[];
    final services = <int, Map<int, Map<int, Uint8List>>>{polled: {}};
    final finished = <int, Set<int>>{polled: {}};
    final orders = <int, List<int>>{};

    FelicaDump dump({required bool complete}) => FelicaDump.ofSystems(
      complete: complete,
      systems: [
        for (final (number, code)
            in (codes.isEmpty ? [(polled, polledCode)] : codes.indexed))
          FelicaSystem(
            code: code,
            services: _ordered(services[number] ?? {}, orders[number] ?? []),
            finishedServices: finished[number] ?? {},
          ),
      ],
    );

    try {
      if (tag.isLite) {
        // A Lite-S has one system and does not list it.
        final blocks = services[polled]![liteService] = {};
        var i = 0;
        while (i < liteBlocks.length) {
          final batch = liteBlocks.skip(i).take(_batchSize).toList();
          i += batch.length;
          final data = await readBlocks(tag.id, liteService, batch);
          if (data != null) {
            blocks.addAll(Map.fromIterables(batch, data));
            continue;
          }
          // One unreadable block fails the batch; read them one by one.
          var readAlone = 0;
          for (final number in batch) {
            final single = await readBlock(tag.id, liteService, number);
            if (single == null) continue;
            blocks[number] = single;
            readAlone++;
          }
          _fitBatch(batch.length, readAlone);
        }
        return dump(complete: true);
      }

      codes = systemCodes ?? await _requestSystemCodes(tag.id);
      onProgress?.call(dump(complete: false));

      for (final service in first) {
        final blocks = services[polled]![service] = {};
        await _readService(
          tag.id,
          service,
          blocks,
          onBlock: onProgress == null
              ? null
              : () => onProgress(dump(complete: false)),
        );
        // A service the card lacks fails at block 0, as an empty one.
        if (blocks.isEmpty) {
          services[polled]!.remove(service);
        } else {
          finished[polled]!.add(service);
        }
      }

      for (var number = 0; number < codes.length; number++) {
        final idm = Felica.systemIdm(tag.id, number);
        final systemServices = services.putIfAbsent(number, () => {});
        final done = finished.putIfAbsent(number, () => {});
        final order = orders[number] = await _searchServices(idm);
        for (final service in order) {
          if (!FelicaDump.readsWithoutEncryption(service)) continue;
          if (systemServices.containsKey(service)) continue;
          await _readService(idm, service, systemServices[service] = {});
          done.add(service);
        }
      }
      return dump(complete: true);
    } catch (error, stackTrace) {
      log('FeliCa read stopped early', error: error, stackTrace: stackTrace);
      return dump(complete: false);
    }
  }

  /// The first batch of [tag]'s blocks, which tells the kind of card apart.
  ///
  /// A card other than a Lite lists its systems first, with Request System
  /// Code; one that does not answer it is taken to have only its polled
  /// system. Then, by system:
  /// - of a Lite or a system 0x12FC, service 0x000B from block 0: an
  ///   Amusement IC's S_PAD0, a Type 3 tag's attribute block. When block 0
  ///   describes an NDEF message, the rest of the blocks holding it are read
  ///   too, so the message shows at once.
  /// - of a system 0x0003, a Suica's newest history records.
  ///
  /// Null when nothing was read, not even the systems. The dump is never
  /// complete: the rest of the card is read after. Throws when the card
  /// does not answer a first batch.
  Future<FelicaDump?> readFirst(Felica tag) async {
    final polled = [(tag.id[0] >> 4, tag.systemCode.firstOrNull ?? 0)];
    var listed = false;
    var systems = polled;
    if (!tag.isLite) {
      try {
        final codes = await _requestSystemCodes(tag.id);
        if (codes.isNotEmpty) {
          systems = codes.indexed.toList();
          listed = true;
        }
      } catch (error, stackTrace) {
        log('FeliCa systems not listed', error: error, stackTrace: stackTrace);
      }
    }

    final read = <int, Map<int, Map<int, Uint8List>>>{};
    for (final (number, code) in systems) {
      final int service;
      if (tag.isLite || code == Felica.ndefSystemCode) {
        service = Felica.ndefService;
      } else if (code == 0x0003) {
        service = Suica.historyService;
      } else {
        continue;
      }
      final blocks = <int, Uint8List>{};
      await _readFirstBatch(Felica.systemIdm(tag.id, number), service, blocks);
      if (blocks.isNotEmpty) read[number] = {service: blocks};
    }
    if (!listed && read.isEmpty) return null;
    return FelicaDump.ofSystems(
      complete: false,
      systems: [
        for (final (number, code) in systems)
          FelicaSystem(code: code, services: read[number] ?? const {}),
      ],
    );
  }

  /// Reads a batch of [service] from block 0 into [blocks], and when it is a
  /// Type 3 tag's, on through the blocks of the NDEF message.
  Future<void> _readFirstBatch(
    Uint8List idm,
    int service,
    Map<int, Uint8List> blocks,
  ) async {
    final next = await _readRange(idm, service, 0, blocks);
    final attribute = service == Felica.ndefService ? blocks[0] : null;
    // Version 1 of the Type 3 mapping; the rest is checked once read.
    if (attribute == null || attribute[0] >> 4 != 1) return;
    final length = attribute[11] << 16 | attribute[12] << 8 | attribute[13];
    final dataBlocks = min(
      (length + 15) ~/ 16,
      attribute[3] << 8 | attribute[4],
    );
    try {
      await _readRange(idm, service, next, blocks, end: dataBlocks + 1);
    } catch (error, stackTrace) {
      log(
        'FeliCa NDEF read stopped early',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Reads blocks of [service] into [blocks] from [start]: one batch, or up
  /// to [end] when given. Returns the block after the last one read; it
  /// stops early at a block the card refuses.
  Future<int> _readRange(
    Uint8List idm,
    int service,
    int start,
    Map<int, Uint8List> blocks, {
    int? end,
  }) async {
    final last = end ?? start + _batchSize;
    var number = start;
    while (number < last) {
      final batch = [
        for (var i = number; i < last && i < number + _batchSize; i++) i,
      ];
      var data = await readBlocks(idm, service, batch);
      if (data == null && batch.length > 1) {
        data = await _singles(idm, service, batch);
        _fitBatch(batch.length, data.length);
      }
      if (data == null || data.isEmpty) break;
      for (final block in data) {
        blocks[number++] = block;
      }
      if (data.length < batch.length) break;
    }
    return number;
  }

  /// Reads [service] into [blocks] from block 0 until the card reports an
  /// error, calling [onBlock] after each block. [blocks] keeps what was read
  /// if the card stops answering.
  Future<void> _readService(
    Uint8List idm,
    int service,
    Map<int, Uint8List> blocks, {
    void Function()? onBlock,
  }) async {
    var number = 0;
    while (number < _maxBlocksPerService) {
      final batch = [for (var i = number; i < number + _batchSize; i++) i];
      // A batch that runs past the end fails whole; the blocks before the
      // end are then read one by one.
      var data = await readBlocks(idm, service, batch);
      if (data == null && batch.length > 1) {
        data = await _singles(idm, service, batch);
        _fitBatch(batch.length, data.length);
      }
      if (data == null || data.isEmpty) return;
      for (final block in data) {
        blocks[number++] = block;
        onBlock?.call();
      }
      if (data.length < batch.length) return;
    }
  }

  /// [batch]'s blocks of [service] read one at a time, stopping at the first
  /// the card refuses.
  Future<List<Uint8List>> _singles(
    Uint8List idm,
    int service,
    List<int> batch,
  ) async {
    final blocks = <Uint8List>[];
    for (final number in batch) {
      final data = await readBlock(idm, service, number);
      if (data == null) break;
      blocks.add(data);
    }
    return blocks;
  }

  /// [services] in the card's [order], then any the card did not list.
  static Map<int, Map<int, Uint8List>> _ordered(
    Map<int, Map<int, Uint8List>> services,
    List<int> order,
  ) => {for (final service in order) service: ?services[service], ...services};

  /// Reads block [number] of [service] with Read Without Encryption. Returns
  /// null when the card answers with an error status, and throws when it
  /// does not answer or answers something else.
  Future<Uint8List?> readBlock(Uint8List idm, int service, int number) async =>
      (await readBlocks(idm, service, [number]))?.single;

  /// Reads blocks [numbers] of [service] in one Read Without Encryption.
  /// Returns null when the card answers with an error status, as it does
  /// when any of them cannot be read, and throws when it does not answer or
  /// answers something else.
  Future<List<Uint8List>?> readBlocks(
    Uint8List idm,
    int service,
    List<int> numbers,
  ) async {
    final response = await _exchange([
      0x06,
      ...idm,
      1,
      service & 0xFF,
      service >> 8,
      numbers.length,
      for (final number in numbers)
        // A two-byte block list element reaches block 255; past it, three.
        if (number <= 0xFF) ...[
          0x80,
          number,
        ] else ...[
          0x00,
          number & 0xFF,
          number >> 8,
        ],
    ], 0x07);
    // Status flags, then the block count and data on success.
    if (response.length < 2) throw const FormatException('No status flags');
    if (response[0] != 0) return null;
    const size = FelicaDump.blockSize;
    if (response.length < 3 + size * numbers.length ||
        response[2] != numbers.length) {
      throw const FormatException('Short Read Without Encryption response');
    }
    return [
      for (var i = 0; i < numbers.length; i++)
        Uint8List.fromList(response.sublist(3 + size * i, 3 + size * (i + 1))),
    ];
  }

  /// The system codes of the card, by system number, from Request System
  /// Code.
  Future<List<int>> _requestSystemCodes(Uint8List idm) async {
    final response = await _exchange([0x0C, ...idm], 0x0D);
    if (response.isEmpty || response.length < 1 + 2 * response[0]) {
      throw const FormatException('Short Request System Code response');
    }
    return [
      for (var i = 0; i < response[0]; i++)
        response[1 + 2 * i] << 8 | response[2 + 2 * i],
    ];
  }

  /// The service codes of the system [idm] names, in the card's order, from
  /// Search Service Code. Areas are skipped.
  Future<List<int>> _searchServices(Uint8List idm) async {
    final services = <int>[];
    for (var index = 0; index < _maxServiceIndex; index++) {
      final response = await _exchange([
        0x0A,
        ...idm,
        index & 0xFF,
        index >> 8,
      ], 0x0B);
      if (response.length < 2) throw const FormatException('No service code');
      final code = response[0] | response[1] << 8;
      if (code == 0xFFFF) return services;
      // An area answers with its code and its end code.
      if (response.length == 2) services.add(code);
    }
    return services;
  }

  /// Sends [command], which starts with its code and an IDm, and returns
  /// the response body after its code and IDm, checking the code is
  /// [responseCode] and the IDm is the one the command named.
  Future<Uint8List> _exchange(List<int> command, int responseCode) async {
    final response = await channel.transceive(
      Uint8List.fromList([command.length + 1, ...command]),
    );
    // The length byte bounds the frame against any bytes after it.
    if (response.length < 10 ||
        response[0] < 10 ||
        response[0] > response.length ||
        response[1] != responseCode ||
        !listEquals(response.sublist(2, 10), command.sublist(1, 9))) {
      throw FormatException(
        'Unexpected FeliCa response to 0x'
        '${command[0].toRadixString(16).padLeft(2, '0')}',
      );
    }
    return Uint8List.sublistView(response, 10, response[0]);
  }
}
