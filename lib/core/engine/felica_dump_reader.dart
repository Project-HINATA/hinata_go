import 'dart:developer';
import 'dart:typed_data';

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

  FelicaDumpReader(this.channel);

  /// Reads [tag]'s blocks. Never throws: if the card stops answering, the
  /// blocks read so far come back in a dump that is not complete.
  ///
  /// The services in [first] are read before the card's services are
  /// listed, and [onFirstBlock] gets the dump after each of their blocks, so
  /// what a card is mostly read for shows as it is read. The finished dump
  /// keeps the card's order of services.
  Future<FelicaDump> read(
    Felica tag, {
    List<int> first = const [],
    void Function(FelicaDump dump)? onFirstBlock,
  }) async {
    final services = <int, Map<int, Uint8List>>{};
    final finished = <int>{};
    var order = <int>[];
    try {
      if (tag.isLite) {
        final blocks = services[liteService] = {};
        for (final number in liteBlocks) {
          final data = await readBlock(tag.id, liteService, number);
          if (data != null) blocks[number] = data;
        }
      } else {
        for (final service in first) {
          final blocks = services[service] = {};
          await _readService(
            tag.id,
            service,
            blocks,
            onBlock: onFirstBlock == null
                ? null
                : () => onFirstBlock(
                    FelicaDump(complete: false, services: services),
                  ),
          );
          // A service the card lacks fails at block 0, as an empty one.
          if (blocks.isEmpty) {
            services.remove(service);
          } else {
            finished.add(service);
          }
        }
        order = await _searchServices(tag.id);
        for (final service in order) {
          if (!FelicaDump.readsWithoutEncryption(service)) continue;
          if (services.containsKey(service)) continue;
          await _readService(tag.id, service, services[service] = {});
          finished.add(service);
        }
      }
      return FelicaDump(complete: true, services: _ordered(services, order));
    } catch (error, stackTrace) {
      log('FeliCa read stopped early', error: error, stackTrace: stackTrace);
      return FelicaDump(
        complete: false,
        services: _ordered(services, order),
        finishedServices: finished,
      );
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
    for (var number = 0; number < _maxBlocksPerService; number++) {
      final data = await readBlock(idm, service, number);
      if (data == null) return;
      blocks[number] = data;
      onBlock?.call();
    }
  }

  /// [services] in the card's [order], then any the card did not list.
  static Map<int, Map<int, Uint8List>> _ordered(
    Map<int, Map<int, Uint8List>> services,
    List<int> order,
  ) => {for (final service in order) service: ?services[service], ...services};

  /// Reads block [number] of [service] with Read Without Encryption. Returns
  /// null when the card answers with an error status, and throws when it
  /// does not answer or answers something else.
  Future<Uint8List?> readBlock(Uint8List idm, int service, int number) async {
    final response = await _exchange([
      0x06,
      ...idm,
      1,
      service & 0xFF,
      service >> 8,
      1,
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
    if (response.length < 3 + FelicaDump.blockSize || response[2] != 1) {
      throw const FormatException('Short Read Without Encryption response');
    }
    return Uint8List.fromList(response.sublist(3, 3 + FelicaDump.blockSize));
  }

  /// The service codes of the polled system, in the card's order, from
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

  /// Sends [command] and returns the response body after its code and IDm,
  /// checking the code is [responseCode].
  Future<Uint8List> _exchange(List<int> command, int responseCode) async {
    final response = await channel.transceive(
      Uint8List.fromList([command.length + 1, ...command]),
    );
    // The length byte bounds the frame against any bytes after it.
    if (response.length < 10 ||
        response[0] < 10 ||
        response[0] > response.length ||
        response[1] != responseCode) {
      throw FormatException(
        'Unexpected FeliCa response to 0x'
        '${command[0].toRadixString(16).padLeft(2, '0')}',
      );
    }
    return Uint8List.sublistView(response, 10, response[0]);
  }
}
