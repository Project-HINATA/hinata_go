import 'dart:collection';
import 'dart:typed_data';

import 'card.dart';

/// One system of a FeliCa card: its system code and the blocks of its
/// services that read without encryption.
class FelicaSystem {
  /// The system code, as Request System Code lists it.
  final int code;

  /// Service code to its blocks, in the card's order of services; each
  /// service's blocks are ordered by block number.
  final Map<int, Map<int, Uint8List>> services;

  /// The services read until the card reported their end, when the read as
  /// a whole stopped early.
  final Set<int> finishedServices;

  FelicaSystem({
    required this.code,
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
      if (blocks.values.any((b) => b.length != FelicaDump.blockSize)) {
        throw ArgumentError('Blocks must be ${FelicaDump.blockSize} bytes');
      }
    }
  }

  int get blockCount =>
      services.values.fold(0, (count, blocks) => count + blocks.length);

  Map<String, dynamic> _toJson({required bool complete}) => {
    'code': code,
    'services': [
      for (final MapEntry(key: service, value: blocks) in services.entries)
        {
          'code': service,
          if (!complete && finishedServices.contains(service)) 'finished': true,
          'blocks': {
            for (final MapEntry(key: number, value: data) in blocks.entries)
              '$number': _hex(data),
          },
        },
    ],
  };

  factory FelicaSystem._fromJson(int code, List<dynamic> servicesJson) {
    final services = <int, Map<int, Uint8List>>{};
    final finishedServices = <int>{};
    for (final service in servicesJson) {
      if (service is! Map<String, dynamic>) continue;
      final serviceCode = service['code'];
      if (serviceCode is! int) continue;
      if (service['finished'] == true) finishedServices.add(serviceCode);
      final blocks = services[serviceCode] = {};
      final blocksJson = service['blocks'] as Map<String, dynamic>? ?? const {};
      for (final MapEntry(:key, :value) in blocksJson.entries) {
        final number = int.tryParse(key);
        if (number == null || value is! String) continue;
        final data = ICCard.hexToBytes(value);
        if (data.length == FelicaDump.blockSize) blocks[number] = data;
      }
    }
    return FelicaSystem(
      code: code,
      services: services,
      finishedServices: finishedServices,
    );
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The blocks of a FeliCa card that read without encryption, by system and
/// service.
class FelicaDump {
  static const blockSize = 16;

  /// Whether every block that reads without encryption was read. False when
  /// the read stopped early, for example because the card left the field.
  final bool complete;

  /// The card's systems, by system number.
  final List<FelicaSystem> systems;

  /// A dump of a card with one system, [systemCode].
  FelicaDump({
    required bool complete,
    Map<int, Map<int, Uint8List>> services = const {},
    Set<int> finishedServices = const {},
    required int systemCode,
  }) : this.ofSystems(
         complete: complete,
         systems: [
           FelicaSystem(
             code: systemCode,
             services: services,
             finishedServices: finishedServices,
           ),
         ],
       );

  FelicaDump.ofSystems({
    required this.complete,
    required List<FelicaSystem> systems,
  }) : systems = List.unmodifiable(systems);

  /// The system codes, by system number.
  List<int> get systemCodes => [for (final system in systems) system.code];

  /// System 0's services, where a card keeps what it is mostly read for.
  Map<int, Map<int, Uint8List>> get services =>
      systems.firstOrNull?.services ?? const {};

  /// Whether [service] of system [system] was read, every block of it.
  bool isServiceComplete(int service, {int system = 0}) {
    if (system >= systems.length) return false;
    final found = systems[system];
    return (complete && found.services.containsKey(service)) ||
        found.finishedServices.contains(service);
  }

  /// Block [number] of system 0's [service], or null when it was not read.
  Uint8List? block(int service, int number) => services[service]?[number];

  int get blockCount =>
      systems.fold(0, (count, system) => count + system.blockCount);

  /// This dump with a later scan's systems and services over its own. The
  /// later scan's copy of a service replaces this one, unless it was cut off
  /// in a service this dump read in full.
  FelicaDump overlaidWith(FelicaDump later) {
    if (later.complete) return later;
    final laterNumbers = {
      for (final (number, system) in later.systems.indexed) system.code: number,
    };
    final merged = <FelicaSystem>[];
    var whole = complete;
    void add(
      int code,
      Map<int, Map<int, Uint8List>> services,
      bool Function(int service) finished,
    ) {
      final done = {
        for (final service in services.keys)
          if (finished(service)) service,
      };
      whole = whole && services.keys.every(done.contains);
      merged.add(
        FelicaSystem(code: code, services: services, finishedServices: done),
      );
    }

    for (final (number, earlier) in systems.indexed) {
      final laterNumber = laterNumbers[earlier.code];
      if (laterNumber == null) {
        add(
          earlier.code,
          earlier.services,
          (service) => isServiceComplete(service, system: number),
        );
        continue;
      }
      final laterSystem = later.systems[laterNumber];
      bool laterDone(int service) =>
          later.isServiceComplete(service, system: laterNumber);
      bool earlierDone(int service) =>
          isServiceComplete(service, system: number);
      bool takeLater(int service) =>
          laterSystem.services.containsKey(service) &&
          (laterDone(service) || !earlierDone(service));
      add(
        earlier.code,
        {
          for (final MapEntry(key: service, value: blocks)
              in earlier.services.entries)
            service: takeLater(service)
                ? laterSystem.services[service]!
                : blocks,
          for (final MapEntry(key: service, value: blocks)
              in laterSystem.services.entries)
            if (!earlier.services.containsKey(service)) service: blocks,
        },
        (service) =>
            takeLater(service) ? laterDone(service) : earlierDone(service),
      );
    }
    final earlierCodes = systemCodes.toSet();
    for (final (number, system) in later.systems.indexed) {
      if (earlierCodes.contains(system.code)) continue;
      add(
        system.code,
        system.services,
        (service) => later.isServiceComplete(service, system: number),
      );
    }
    // Only a dump that had every service can still have them all.
    return FelicaDump.ofSystems(complete: whole, systems: merged);
  }

  /// Whether [service] can be read without encryption, judged from the
  /// attribute in its low six bits.
  static bool readsWithoutEncryption(int service) {
    final attribute = service & 0x3F;
    return attribute >= 0x08 && attribute <= 0x17 && attribute.isOdd;
  }

  Map<String, dynamic> toJson() => {
    'complete': complete,
    'systems': [
      for (final system in systems) system._toJson(complete: complete),
    ],
  };

  /// Reads a dump. One saved before dumps kept their systems is a single
  /// system, [legacySystemCode].
  factory FelicaDump.fromJson(
    Map<String, dynamic> json, {
    int legacySystemCode = 0,
  }) {
    final complete = json['complete'] as bool? ?? false;
    final systemsJson = json['systems'];
    if (systemsJson is! List<dynamic>) {
      return FelicaDump.ofSystems(
        complete: complete,
        systems: [
          FelicaSystem._fromJson(
            legacySystemCode,
            json['services'] as List<dynamic>? ?? const [],
          ),
        ],
      );
    }
    return FelicaDump.ofSystems(
      complete: complete,
      systems: [
        for (final system in systemsJson)
          if (system is Map<String, dynamic> && system['code'] is int)
            FelicaSystem._fromJson(
              system['code'] as int,
              system['services'] as List<dynamic>? ?? const [],
            ),
      ],
    );
  }
}
