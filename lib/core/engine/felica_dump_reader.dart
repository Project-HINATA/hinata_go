import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../models/card/felica.dart';
import '../../models/card/felica_dump.dart';

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

  /// How many blocks one Read Without Encryption asks for. A HINATA reader
  /// passes a PN532 frame in one HID report, which holds two.
  final int blocksPerRead;

  FelicaDumpReader(this.channel, {this.blocksPerRead = 2});

  /// Reads [tag]'s blocks, in each of its systems. Never throws: if the card
  /// stops answering, the blocks read so far come back in a dump that is not
  /// complete.
  ///
  /// The card's systems are listed first, then the services in [first] are
  /// read in the polled system before the rest. [onProgress] gets the dump
  /// once the systems are known and after each block of [first], so the
  /// system codes and what a card is mostly read for show as they are read.
  /// The finished dump keeps the card's order of systems and services.
  Future<FelicaDump> read(
    Felica tag, {
    List<int> first = const [],
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
        for (var i = 0; i < liteBlocks.length; i += blocksPerRead) {
          final batch = liteBlocks.skip(i).take(blocksPerRead).toList();
          final data = await readBlocks(tag.id, liteService, batch);
          if (data != null) {
            blocks.addAll(Map.fromIterables(batch, data));
            continue;
          }
          // One unreadable block fails the batch; read them one by one.
          for (final number in batch) {
            final single = await readBlock(tag.id, liteService, number);
            if (single != null) blocks[number] = single;
          }
        }
        return dump(complete: true);
      }

      codes = await _requestSystemCodes(tag.id);
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
      final batch = [for (var i = number; i < number + blocksPerRead; i++) i];
      // A batch that runs past the end fails whole; the blocks before the
      // end are then read one by one.
      final data =
          await readBlocks(idm, service, batch) ??
          (batch.length > 1 ? await _singles(idm, service, number) : null);
      if (data == null || data.isEmpty) return;
      for (final block in data) {
        blocks[number++] = block;
        onBlock?.call();
      }
      if (data.length < batch.length) return;
    }
  }

  /// The blocks of [service] from [start] read one at a time, up to a batch
  /// and stopping at the first the card refuses.
  Future<List<Uint8List>> _singles(
    Uint8List idm,
    int service,
    int start,
  ) async {
    final blocks = <Uint8List>[];
    for (var number = start; number < start + blocksPerRead; number++) {
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
