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

  /// The services read until the card reported their end, when the read as
  /// a whole stopped early. Every service is, in a complete dump.
  final Set<int> finishedServices;

  FelicaDump({
    required this.complete,
    Map<int, Map<int, Uint8List>> services = const {},
    Set<int> finishedServices = const {},
  }) : finishedServices = Set.unmodifiable(finishedServices),
       services = Map.unmodifiable({
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

  /// Whether [service] was read, every block of it.
  bool isServiceComplete(int service) =>
      (complete && services.containsKey(service)) ||
      finishedServices.contains(service);

  /// This dump with a later scan's services over its own. The later scan's
  /// copy of a service replaces this one, unless it was cut off in a service
  /// this dump read in full.
  FelicaDump overlaidWith(FelicaDump later) {
    if (later.complete) return later;
    bool takeLater(int service) =>
        later.services.containsKey(service) &&
        (later.isServiceComplete(service) || !isServiceComplete(service));
    final merged = {
      for (final MapEntry(key: service, value: blocks) in services.entries)
        service: takeLater(service) ? later.services[service]! : blocks,
      ...{
        for (final MapEntry(key: service, value: blocks)
            in later.services.entries)
          if (!services.containsKey(service)) service: blocks,
      },
    };
    final finished = {
      for (final service in merged.keys)
        if (takeLater(service)
            ? later.isServiceComplete(service)
            : isServiceComplete(service))
          service,
    };
    // Only a dump that had every service can still have them all.
    final whole = complete && merged.keys.every(finished.contains);
    return FelicaDump(
      complete: whole,
      services: merged,
      finishedServices: whole ? const {} : finished,
    );
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
          if (!complete && finishedServices.contains(code)) 'finished': true,
          'blocks': {
            for (final MapEntry(key: number, value: data) in blocks.entries)
              '$number': _hex(data),
          },
        },
    ],
  };

  factory FelicaDump.fromJson(Map<String, dynamic> json) {
    final services = <int, Map<int, Uint8List>>{};
    final finishedServices = <int>{};
    for (final service in json['services'] as List<dynamic>? ?? const []) {
      if (service is! Map<String, dynamic>) continue;
      final code = service['code'];
      if (code is! int) continue;
      if (service['finished'] == true) finishedServices.add(code);
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
      finishedServices: finishedServices,
    );
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
