import 'dart:collection';
import 'dart:typed_data';

import 'card.dart';

/// The blocks of a FeliCa card that read without encryption, by service.
class FelicaDump {
  static const blockSize = 16;

  /// Whether every block that reads without encryption was read. False when
  /// the read stopped early, for example because the card left the field.
  final bool complete;

  /// Service code to its blocks, in the order the services were read; each
  /// service's blocks are ordered by block number.
  final Map<int, Map<int, Uint8List>> services;

  FelicaDump({
    required this.complete,
    Map<int, Map<int, Uint8List>> services = const {},
  }) : services = Map.unmodifiable({
         for (final entry in services.entries)
           entry.key: Map<int, Uint8List>.unmodifiable(
             SplayTreeMap<int, Uint8List>.of(entry.value),
           ),
       }) {
    for (final blocks in services.values) {
      if (blocks.values.any((block) => block.length != blockSize)) {
        throw ArgumentError('Blocks must be $blockSize bytes');
      }
    }
  }

  /// Block [number] of [service], or null when it was not read.
  Uint8List? block(int service, int number) => services[service]?[number];

  int get blockCount =>
      services.values.fold(0, (count, blocks) => count + blocks.length);

  /// Whether [service] can be read without encryption, judged from the
  /// attribute in its low six bits.
  static bool readsWithoutEncryption(int service) {
    final attribute = service & 0x3F;
    return attribute >= 0x08 && attribute <= 0x17 && attribute.isOdd;
  }

  Map<String, dynamic> toJson() => {
    'complete': complete,
    'services': [
      for (final MapEntry(key: code, value: blocks) in services.entries)
        {
          'code': code,
          'blocks': {
            for (final MapEntry(key: number, value: data) in blocks.entries)
              '$number': _hex(data),
          },
        },
    ],
  };

  factory FelicaDump.fromJson(Map<String, dynamic> json) {
    final services = <int, Map<int, Uint8List>>{};
    for (final service in json['services'] as List<dynamic>? ?? const []) {
      if (service is! Map<String, dynamic>) continue;
      final code = service['code'];
      if (code is! int) continue;
      final blocks = services[code] = {};
      final blocksJson = service['blocks'] as Map<String, dynamic>? ?? const {};
      for (final MapEntry(:key, :value) in blocksJson.entries) {
        final number = int.tryParse(key);
        if (number == null || value is! String) continue;
        final data = ICCard.hexToBytes(value);
        if (data.length == blockSize) blocks[number] = data;
      }
    }
    return FelicaDump(
      complete: json['complete'] as bool? ?? false,
      services: services,
    );
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
