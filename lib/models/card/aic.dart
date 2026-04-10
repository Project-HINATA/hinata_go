import 'dart:typed_data';

import 'card.dart';
import 'felica.dart';

class Aic extends Felica implements HasAccessCode {
  final Uint8List accessCode;
  Aic(
    super.id,
    super.pmm,
    super.systemCode,
    this.accessCode, {
    super.persistedEpass,
  });

  @override
  String get accessCodeString =>
      accessCode.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get manufacturer {
    final prefix = accessCodeString.substring(0, 2);

    return switch (prefix) {
      '50' => 'SEGA',
      '51' => 'Bandai Namco',
      '52' => 'KONAMI',
      '53' => 'Taito',
      _ => 'Unknown',
    };
  }

  @override
  String get name => "Amusement IC";

  @override
  String? get logoPath => "assets/cardlogo/aic.svg";

  @override
  String? get type => "aic";

  @override
  String? get value => "$idString:$accessCodeString";

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'accessCode': accessCodeString};
  }

  factory Aic.fromJson(Map<String, dynamic> json) {
    final felica = Felica.fromJson(json);
    return Aic(
      felica.id,
      felica.pmm,
      felica.systemCode,
      ICCard.hexToBytes(json['accessCode'] as String? ?? ''),
      persistedEpass: json['epass'] as String?,
    );
  }
}

extension ToAIC on Felica {
  Aic toAic(Uint8List accessCode) => Aic(id, pmm, systemCode, accessCode);
}
