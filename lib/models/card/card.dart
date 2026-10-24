import 'dart:typed_data';

import 'ndef.dart';
import 'aic.dart';
import 'aime.dart';
import 'banapass.dart';
import 'card_tag.dart';
import 'felica.dart';
import 'iso15693.dart';
import 'iso14443a.dart';
import 'nesica.dart';
import 'suica.dart';
import 'tunion.dart';

export 'card_tag.dart';

class ICCard {
  final Uint8List? _id;
  final List<CardTag> tags;

  ICCard(Uint8List id, {this.tags = const []}) : _id = id;
  ICCard._data({this.tags = const []}) : _id = null;

  /// Compatibility projection; data without a physical tag has no chip ID.
  Uint8List get id => _id ?? Uint8List(0);
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
    return id.isNotEmpty && idString == other.idString;
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': _bytesToHex(id),
      if (tags.isNotEmpty) 'tags': tags.map((t) => t.toJson()).toList(),
    };
  }

  Map<String, dynamic> toRemoteJson({bool includeCanonicalFields = true}) =>
      toJson();

  /// Dispatch deserialization to the correct subclass based on `type`.
  static ICCard fromJson(Map<String, dynamic> json, {String? source}) {
    final type = json['type'] as String?;
    switch (type) {
      case 'ndef':
        return NdefCard.fromJson(json);
      case 'aic':
        return Aic.fromJson(json);
      case 'aime':
        return Aime.fromJson(json, source: source);
      case 'felica':
        return Felica.fromJson(json);
      case 'banapass':
      case 'mifare': // Legacy V1 and persisted data.
        return Banapass.fromJson(json, source: source);
      case 'iso14443':
        return Iso14443.fromJson(json);
      case 'iso15693':
        return Iso15693.fromJson(json);
      case 'nesica':
        return Nesica.fromJson(json);
      case 'suica':
        return Suica.fromJson(json);
      case 'tunion':
        return TUnion.fromJson(json);
      default:
        return ICCard(
          hexToBytes(json['id'] as String? ?? ''),
          tags:
              (json['tags'] as List<dynamic>?)
                  ?.map(CardTag.fromJson)
                  .toList() ??
              const [],
        );
    }
  }

  /// Reconstruct from flat type + value strings (e.g. from [ScanLog]).
  static ICCard fromTypeAndValue(String type, String value) {
    if (type == 'nesica') {
      return Nesica.fromJson({'type': type, 'id': '', 'serial': value});
    }
    if (type == 'banapass' && RegExp(r'^\d{20}$').hasMatch(value)) {
      return Banapass.fromAccessCode(accessCode: value, dualKey: true);
    }
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

/// Portable application data, optionally accompanied by a scanned tag snapshot.
abstract class CardData extends ICCard {
  final ICCard? physicalCard;

  CardData({this.physicalCard, List<CardTag> tags = const []})
    : super._data(tags: {...tags, ...?physicalCard?.tags}.toList()) {
    if (physicalCard is CardData) {
      throw const FormatException('Physical metadata cannot contain card data');
    }
  }

  bool get hasPhysicalCard => physicalCard != null;

  @override
  Uint8List get id => physicalCard?.id ?? Uint8List(0);

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'physicalCard': physicalCard?.toJson(),
    if (tags.isNotEmpty) 'tags': tags.map((tag) => tag.toJson()).toList(),
  };

  @override
  Map<String, dynamic> toRemoteJson({bool includeCanonicalFields = true}) {
    final payload = toJson()..remove('physicalCard');
    // SET_CARD_V2 still requires the flat chip fields, even for portable data.
    return {
      if (this is Aime || this is Banapass) ...{
        'sak': 8,
        'atqa': this is Banapass ? 0x0400 : 0x0004,
      },
      ...?physicalCard?.toJson(),
      ...payload,
      'id': idString,
    };
  }

  static ICCard? readPhysicalCard(Map<String, dynamic> json, {String? source}) {
    if (json.containsKey('physicalCard')) {
      final physical = json['physicalCard'] as Map<String, dynamic>?;
      if (physical == null) return null;
      if (const {
        'aime',
        'banapass',
        'mifare',
        'ndef',
      }.contains(physical['type'])) {
        throw const FormatException(
          'Physical metadata cannot contain card data',
        );
      }
      return ICCard.fromJson(physical);
    }

    final id = json['id'] as String? ?? '';
    if (id.isEmpty || _isLegacyPlaceholder(json, source)) return null;
    if (const {'aime', 'banapass', 'mifare'}.contains(json['type'])) {
      return Iso14443.fromJson(json);
    }
    return ICCard(ICCard.hexToBytes(id));
  }

  static bool _isLegacyPlaceholder(Map<String, dynamic> json, String? source) {
    if (source != 'Direct' && source != 'QR') return false;
    return json['type'] == 'aime' &&
        json['id'] == '00000000' &&
        json['sak'] == 8 &&
        json['atqa'] == 4;
  }
}

abstract interface class HasAccessCode {
  String? get accessCodeString;
}

abstract interface class HasEPass {
  String? get epass;
}
