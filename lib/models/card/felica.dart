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

  /// FeliCa Lite and Lite-S, told apart from other ICs by the IC type in the
  /// PMm. They have one block map, read through service 0x000B.
  bool get isLite => pmm.length == 8 && (pmm[1] == 0xF0 || pmm[1] == 0xF1);

  /// Whether every block that reads without encryption was saved.
  bool get isFullyRead => dump?.complete ?? false;

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
    return Felica(
      ICCard.hexToBytes(json['id'] as String? ?? ''),
      ICCard.hexToBytes(json['pmm'] as String? ?? ''),
      Uint16List.fromList(
        (json['systemCode'] as List<dynamic>?)?.cast<int>() ?? [],
      ),
      tags:
          (json['tags'] as List<dynamic>?)?.map(CardTag.fromJson).toList() ??
          const [],
      dump: json['dump'] is Map<String, dynamic>
          ? FelicaDump.fromJson(json['dump'] as Map<String, dynamic>)
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
