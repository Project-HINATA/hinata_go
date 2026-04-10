import 'dart:typed_data';

import 'package:cardcipher/bana.dart';

import 'card.dart';
import 'iso14443a.dart';

class Banapass extends Iso14443 implements HasAccessCode {
  final Uint8List block1;
  final Uint8List? block2;
  final String? _persistedAccessCode;

  Banapass(
    super.id,
    super.sak,
    super.atqa,
    this.block1,
    this.block2, {
    String? persistedAccessCode,
  }) : _persistedAccessCode = persistedAccessCode;

  String get block1Hex =>
      block1.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get block2Hex => block2 != null
      ? block2!.map((e) => e.toRadixString(16).padLeft(2, '0')).join()
      : '';

  @override
  late final String? accessCodeString =
      _persistedAccessCode ?? _computeAccessCodeString();

  @override
  String get name => "Banapass";

  @override
  String? get type => "mifare";

  @override
  String? get value => "$block1Hex$block2Hex";

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'block1': block1Hex,
      'block2': block2 != null ? block2Hex : null,
      if (accessCodeString != null) 'accessCode': accessCodeString,
    };
  }

  factory Banapass.fromJson(Map<String, dynamic> json) {
    final iso = Iso14443.fromJson(json);
    return Banapass(
      iso.id,
      iso.sak,
      iso.atqa,
      ICCard.hexToBytes(json['block1'] as String? ?? ''),
      json['block2'] != null
          ? ICCard.hexToBytes(json['block2'] as String)
          : null,
      persistedAccessCode: json['accessCode'] as String?,
    );
  }

  String? _computeAccessCodeString() {
    try {
      return nbgiGetAccessCode(block1)?.accessCode;
    } catch (_) {
      return null;
    }
  }
}

extension ToBanapass on Iso14443 {
  Banapass toBanapass(Uint8List block1, Uint8List? block2) =>
      Banapass(id, sak, atqa, block1, block2);
}
