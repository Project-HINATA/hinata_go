import 'dart:typed_data';

import 'package:cardcipher/epass.dart';

import 'card.dart';
import 'felica_dump.dart';

BigInt bytesToBigInt(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (int i = 0; i < bytes.length; i++) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

class Felica extends ICCard implements HasEPass {
  final Uint8List pmm;
  final Uint16List systemCode;

  /// The blocks read from the card; null when none were saved with it.
  final FelicaDump? dump;

  Felica(super.id, this.pmm, this.systemCode, {super.tags, this.dump});

  /// A card as polling found it, with the system code it answered. A Lite
  /// has one system, 0x88B4, though it may answer polling as 0x12FC, so it
  /// is always saved and compared as 0x88B4.
  factory Felica.polled(Uint8List id, Uint8List pmm, Uint16List systemCode) {
    final card = Felica(id, pmm, systemCode);
    return card.isLite
        ? Felica(id, pmm, Uint16List.fromList([liteSystemCode]))
        : card;
  }

  /// The system code of a FeliCa Lite or Lite-S.
  static const liteSystemCode = 0x88B4;

  /// The system code of an NFC Forum Type 3 tag, which holds NDEF.
  static const ndefSystemCode = 0x12FC;

  /// The Type 3 service whose block 0 describes the NDEF message and whose
  /// later blocks hold it.
  static const ndefService = 0x000B;

  /// The Lite-S MC block, whose SYS_OP byte enables NDEF.
  static const _liteMcBlock = 0x88;

  /// FeliCa Lite, Lite-S and FeliCa Link in Lite-S mode, told apart from
  /// other ICs by the IC type in the PMm. They have one block map, read
  /// through service 0x000B.
  bool get isLite =>
      pmm.length == 8 && (pmm[1] == 0xF0 || pmm[1] == 0xF1 || pmm[1] == 0xF2);

  /// The NDEF message the card holds as an NFC Forum Type 3 tag, read from
  /// its saved blocks; null when it holds none, or not every block of it
  /// was saved.
  ///
  /// A Lite keeps it in its one system. Any other card keeps it in the
  /// system 0x12FC.
  late final Uint8List? ndefMessage = _readNdefMessage();

  Uint8List? _readNdefMessage() {
    final systems = dump?.systems ?? const [];
    final system = isLite
        ? systems.firstOrNull
        : systems.where((s) => s.code == ndefSystemCode).firstOrNull;
    final blocks = system?.services[ndefService];
    if (blocks == null) return null;
    if (isLite) {
      // A Lite-S answers as a Type 3 tag only with SYS_OP set to 0x01.
      final mc = blocks[_liteMcBlock];
      if (mc != null && mc[3] != 0x01) return null;
    }
    final attribute = blocks[0];
    if (attribute == null || attribute[0] >> 4 != 1 || attribute[9] != 0) {
      return null;
    }
    final checksum = attribute.take(14).fold(0, (sum, b) => sum + b) & 0xFFFF;
    if (checksum != (attribute[14] << 8 | attribute[15])) return null;
    final length = attribute[11] << 16 | attribute[12] << 8 | attribute[13];
    final dataBlocks = (length + 15) ~/ 16;
    if (length == 0 || dataBlocks > (attribute[3] << 8 | attribute[4])) {
      return null;
    }
    final bytes = BytesBuilder();
    for (var number = 1; number <= dataBlocks; number++) {
      final block = blocks[number];
      if (block == null) return null;
      bytes.add(block);
    }
    return Uint8List.sublistView(bytes.toBytes(), 0, length);
  }

  /// Whether every block that reads without encryption was saved.
  bool get isFullyRead => dump?.complete ?? false;

  /// The IDm a card with [idm] answers with for its system [number]: the
  /// system number is the high nibble of the first byte.
  static Uint8List systemIdm(Uint8List idm, int number) =>
      Uint8List.fromList(idm)..[0] = (idm[0] & 0x0F) | (number << 4);

  String get pmmString =>
      pmm.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get fakeAccessCode => fakeAccessCodeString;

  String get fakeAccessCodeString =>
      bytesToBigInt(id).toString().padLeft(20, '0');

  @override
  late final String? epass = _computeEpass();

  @override
  String get name => "Felica";

  @override
  String? get type => "felica";

  @override
  String? get gamePayload => idString;

  @override
  String get showedValue => idString.toUpperCase();

  String get systemCodeDisplay => systemCode
      .map((e) => e.toRadixString(16).padLeft(4, '0').toUpperCase())
      .join(', ');

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'pmm': pmmString,
      'systemCode': systemCode.toList(),
      if (dump != null) 'dump': dump!.toJson(),
    };
  }

  /// Remote instances take the card's identity, not its blocks.
  @override
  Map<String, dynamic> toRemoteJson({bool includeCanonicalFields = true}) =>
      toJson()..remove('dump');

  factory Felica.fromJson(Map<String, dynamic> json) {
    final systemCode = Uint16List.fromList(
      (json['systemCode'] as List<dynamic>?)?.cast<int>() ?? [],
    );
    return Felica(
      ICCard.hexToBytes(json['id'] as String? ?? ''),
      ICCard.hexToBytes(json['pmm'] as String? ?? ''),
      systemCode,
      tags:
          (json['tags'] as List<dynamic>?)?.map(CardTag.fromJson).toList() ??
          const [],
      dump: json['dump'] is Map<String, dynamic>
          ? FelicaDump.fromJson(
              json['dump'] as Map<String, dynamic>,
              legacySystemCode: systemCode.firstOrNull ?? 0,
            )
          : null,
    );
  }

  String? _computeEpass() {
    try {
      return EPass.encode(idString.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}
