import 'dart:typed_data';

import 'card.dart';
import 'iso14443a.dart';

enum InvalidMifareReason { readFailure, invalidData }

class InvalidMifareCard extends Iso14443 {
  final String? unusableAccessCode;
  final Uint8List? block1;
  final Uint8List? block2;
  final InvalidMifareReason reason;

  InvalidMifareCard(
    super.id,
    super.sak,
    super.atqa, {
    this.unusableAccessCode,
    this.block1,
    this.block2,
    this.reason = InvalidMifareReason.invalidData,
  });

  String? get block1Hex => block1 != null ? _bytesToHex(block1!) : null;

  String? get block2Hex => block2 != null ? _bytesToHex(block2!) : null;

  @override
  String get name => 'Unknown';

  @override
  String? get type => 'unknown';

  @override
  String? get value => null;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'type': type,
      'reason': reason.name,
      if (unusableAccessCode != null) 'accessCode': unusableAccessCode,
      if (block1 != null) 'block1': block1Hex,
      if (block2 != null) 'block2': block2Hex,
    };
  }

  factory InvalidMifareCard.fromJson(Map<String, dynamic> json) {
    final iso = Iso14443.fromJson(json);
    return InvalidMifareCard(
      iso.id,
      iso.sak,
      iso.atqa,
      unusableAccessCode: json['accessCode'] as String?,
      block1: json['block1'] != null
          ? ICCard.hexToBytes(json['block1'] as String)
          : null,
      block2: json['block2'] != null
          ? ICCard.hexToBytes(json['block2'] as String)
          : null,
      reason: _reasonFromJson(json['reason'] as String?),
    );
  }

  static InvalidMifareReason _reasonFromJson(String? value) {
    return InvalidMifareReason.values.firstWhere(
      (reason) => reason.name == value,
      orElse: () => InvalidMifareReason.invalidData,
    );
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}

extension ToInvalidMifareCard on Iso14443 {
  InvalidMifareCard toInvalidMifareCard({
    String? unusableAccessCode,
    Uint8List? block1,
    Uint8List? block2,
    InvalidMifareReason reason = InvalidMifareReason.invalidData,
  }) {
    return InvalidMifareCard(
      id,
      sak,
      atqa,
      unusableAccessCode: unusableAccessCode,
      block1: block1,
      block2: block2,
      reason: reason,
    );
  }
}
