import 'dart:typed_data';

import 'aic.dart';
import 'aime.dart';
import 'banapass.dart';
import 'felica.dart';
import 'invalid_mifare.dart';
import 'iso15693.dart';
import 'iso14443a.dart';
import 'suica.dart';
import 'tunion.dart';

class ICCard {
  final Uint8List id;
  ICCard(this.id);
  String get idString =>
      id.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  String get name => "Generic IC Card";

  String? get logoPath => null;

  String? get type => null;

  String? get gamePayload => null;

  /// User-facing display value based on card type.
  String get showedValue => idString.toUpperCase();

  /// Checks if this card is logically or physically the same card as [other].
  bool isSameCard(ICCard other) {
    if (type != other.type) return false;

    // For cards with access codes (Aime, Banapass, AIC), compare their access codes
    if (this is HasAccessCode && other is HasAccessCode) {
      final ac1 = (this as HasAccessCode).accessCodeString;
      final ac2 = (other as HasAccessCode).accessCodeString;
      if (ac1 != null && ac2 != null && ac1.isNotEmpty && ac2.isNotEmpty) {
        return ac1 == ac2;
      }
    }

    // For China T-Union transit cards, compare public card numbers
    if (this is TUnion && other is TUnion) {
      return (this as TUnion).cardNumber == other.cardNumber;
    }

    // For other cards, compare physical chip IDs (UID / IDm)
    return idString == other.idString;
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'id': _bytesToHex(id)};
  }

  /// Dispatch deserialization to the correct subclass based on `type`.
  static ICCard fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'aic':
        return Aic.fromJson(json);
      case 'aime':
        return Aime.fromJson(json);
      case 'felica':
        return Felica.fromJson(json);
      case 'mifare':
        return Banapass.fromJson(json);
      case 'unknown':
        return InvalidMifareCard.fromJson(json);
      case 'iso14443':
        return Iso14443.fromJson(json);
      case 'iso15693':
        return Iso15693.fromJson(json);
      case 'suica':
        return Suica.fromJson(json);
      case 'tunion':
        return TUnion.fromJson(json);
      default:
        return ICCard(hexToBytes(json['id'] as String? ?? ''));
    }
  }

  /// Reconstruct from flat type + value strings (e.g. from [ScanLog]).
  static ICCard fromTypeAndValue(String type, String value) {
    return fromJson({
      'type': type,
      'id': type == 'iso15693' ? value : '',
      'accessCode': value,
      'block1': value,
    });
  }

  // --- Hex utilities ---

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    if (cleanHex.isEmpty) return Uint8List(0);
    final length = cleanHex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

abstract interface class HasAccessCode {
  String? get accessCodeString;
}

abstract interface class HasEPass {
  String? get epass;
}
