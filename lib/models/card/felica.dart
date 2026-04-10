import 'dart:typed_data';

import 'package:cardcipher/epass.dart';

import 'card.dart';

BigInt bytesToBigInt(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (int i = 0; i < bytes.length; i++) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

class Felica extends ICCard {
  final Uint8List pmm;
  final Uint16List systemCode;
  Felica(super.id, this.pmm, this.systemCode);

  String get pmmString =>
      pmm.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get fakeAccessCodeString =>
      bytesToBigInt(id).toString().padLeft(20, '0');

  String? get epass {
    try {
      return EPass.encode(idString.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  @override
  String get name => "Felica";

  @override
  String? get type => "felica";

  @override
  String? get value => idString;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'pmm': pmmString,
      'systemCode': systemCode.toList(),
    };
  }

  factory Felica.fromJson(Map<String, dynamic> json) {
    return Felica(
      ICCard.hexToBytes(json['id'] as String? ?? ''),
      ICCard.hexToBytes(json['pmm'] as String? ?? ''),
      Uint16List.fromList(
        (json['systemCode'] as List<dynamic>?)?.cast<int>() ?? [],
      ),
    );
  }
}
