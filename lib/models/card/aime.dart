import 'dart:typed_data';

import 'card.dart';
import 'iso14443a.dart';

class Aime extends Iso14443 {
  final Uint8List accessCode;
  Aime(super.id, super.sak, super.atqa, this.accessCode);

  String get accessCodeString =>
      accessCode.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  @override
  String get name => "Aime";

  @override
  String? get type => "aime";

  @override
  String? get value => accessCodeString;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'accessCode': accessCodeString};
  }

  factory Aime.fromJson(Map<String, dynamic> json) {
    final iso = Iso14443.fromJson(json);
    return Aime(
      iso.id,
      iso.sak,
      iso.atqa,
      ICCard.hexToBytes(json['accessCode'] as String? ?? ''),
    );
  }
}

extension ToAime on Iso14443 {
  Aime toAime(Uint8List accessCode) => Aime(id, sak, atqa, accessCode);
}
