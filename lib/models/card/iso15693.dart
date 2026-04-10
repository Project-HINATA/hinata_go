import 'package:cardcipher/epass.dart';

import 'card.dart';

class Iso15693 extends ICCard implements HasEPass {
  final String? _persistedEpass;

  Iso15693(super.id, {String? persistedEpass})
    : _persistedEpass = persistedEpass;

  @override
  late final String? epass = _persistedEpass ?? _computeEpass();

  @override
  String get name => 'ISO15693 Card';

  @override
  String? get type => 'iso15693';

  @override
  String? get value => idString;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), if (epass != null) 'epass': epass};
  }

  factory Iso15693.fromJson(Map<String, dynamic> json) {
    return Iso15693(
      ICCard.hexToBytes(json['id'] as String? ?? ''),
      persistedEpass: json['epass'] as String?,
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
