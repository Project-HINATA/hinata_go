import 'package:flutter/widgets.dart';
import 'package:hinata_go/l10n/l10n.dart';

/// Represents a card tag badge with localized display and search capabilities.
@immutable
class CardTag {
  /// Unique identifier for the tag (e.g. 'tunion', 'suica', 'iso_dep', 'issuer:大连明珠卡').
  final String id;

  /// Custom/dynamic display name (e.g. for card issuer names without official English translations).
  final String? customName;

  const CardTag(this.id, [this.customName]);

  // --- Predefined Constant Tags ---

  /// China T-Union (交通联合)
  static const tUnion = CardTag('tunion');

  /// Japan Transit IC (交通系 IC)
  static const japanTransit = CardTag('japan_transit');

  /// Protocols
  static const isoDep = CardTag('iso_dep');
  static const felica = CardTag('felica');
  static const mifareClassic = CardTag('mifare_classic');
  static const iso14443a = CardTag('iso_14443a');
  static const iso15693 = CardTag('iso_15693');

  /// Standard & Brand Tags
  static const amusementIc = CardTag('amusement_ic');
  static const aime = CardTag('aime');
  static const banapass = CardTag('banapass');
  static const suica = CardTag('suica');
  static const sega = CardTag('sega');
  static const bandaiNamco = CardTag('bandai_namco');
  static const konami = CardTag('konami');
  static const taito = CardTag('taito');

  // --- Dynamic Factories ---

  /// Creates an issuer tag that preserves its native original name (e.g. '大连明珠卡').
  static CardTag issuer(String name) => CardTag('issuer:$name', name);

  /// Creates a custom user-defined tag.
  static CardTag custom(String name) => CardTag(name, name);

  // --- Localization & Display ---

  /// Returns the localized display label using global [l10n].
  String get label => localizedName();

  /// Returns the localized display label using [l10n] or an optional custom [customL10n].
  String localizedName([AppLocalizations? customL10n]) {
    final activeL10n = customL10n ?? l10n;
    if (customName != null && customName!.isNotEmpty) {
      return customName!;
    }
    switch (id) {
      case 'tunion':
        return activeL10n.tagTUnion;
      case 'japan_transit':
        return activeL10n.tagJapanTransit;
      case 'iso_dep':
        return 'ISO-DEP';
      case 'felica':
        return 'FeliCa';
      case 'mifare_classic':
        return 'MIFARE Classic';
      case 'iso_14443a':
        return 'ISO 14443 Type A';
      case 'iso_15693':
        return 'ISO 15693';
      case 'amusement_ic':
        return 'Amusement IC';
      case 'aime':
        return 'Aime';
      case 'banapass':
        return 'Banapass';
      case 'suica':
        return 'Suica';
      case 'sega':
        return 'SEGA';
      case 'bandai_namco':
        return 'BANDAI NAMCO';
      case 'konami':
        return 'Konami Amusement';
      case 'taito':
        return 'TAITO';
      default:
        if (id.startsWith('issuer:')) {
          return id.substring(7);
        }
        return id;
    }
  }

  // --- Search / Filter Matching ---

  /// Checks if this tag matches a given query string (by ID, custom name, or localized name).
  bool matchesSearch(String query, [AppLocalizations? customL10n]) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;

    if (id.toLowerCase().contains(cleanQuery)) return true;
    if (customName != null && customName!.toLowerCase().contains(cleanQuery)) {
      return true;
    }
    final activeL10n = customL10n ?? l10n;
    if (localizedName(activeL10n).toLowerCase().contains(cleanQuery)) {
      return true;
    }
    return false;
  }

  // --- Serialization & Deserialization ---

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (customName != null) 'name': customName,
    };
  }

  factory CardTag.fromJson(dynamic json) {
    if (json is String) {
      return CardTag.fromRawString(json);
    }
    if (json is Map<String, dynamic>) {
      final id = json['id'] as String? ?? '';
      final name = json['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return CardTag(id, name);
      }
      return CardTag.fromRawString(id);
    }
    return CardTag.custom(json.toString());
  }

  factory CardTag.fromRawString(String str) {
    switch (str) {
      case '交通联合':
      case 'China T-Union':
      case 'tunion':
        return CardTag.tUnion;
      case '交通系 IC':
      case '交通系IC':
      case 'Japan Transit IC':
      case 'Transit IC':
      case 'japan_transit':
        return CardTag.japanTransit;
      case 'ISO-DEP':
      case 'iso_dep':
        return CardTag.isoDep;
      case 'FeliCa':
      case 'felica':
        return CardTag.felica;
      case 'MIFARE Classic':
      case 'mifare_classic':
        return CardTag.mifareClassic;
      case 'ISO 14443 Type A':
      case 'iso_14443a':
        return CardTag.iso14443a;
      case 'ISO 15693':
      case 'iso_15693':
        return CardTag.iso15693;
      case 'Amusement IC':
      case 'amusement_ic':
        return CardTag.amusementIc;
      case 'Aime':
      case 'aime':
        return CardTag.aime;
      case 'Banapass':
      case 'banapass':
        return CardTag.banapass;
      case 'Suica':
      case 'suica':
        return CardTag.suica;
      case 'SEGA':
      case 'sega':
        return CardTag.sega;
      case 'BANDAI NAMCO':
      case 'bandai_namco':
        return CardTag.bandaiNamco;
      case 'Konami Amusement':
      case 'konami':
        return CardTag.konami;
      case 'TAITO':
      case 'taito':
        return CardTag.taito;
      default:
        return CardTag.issuer(str);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardTag &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          customName == other.customName;

  @override
  int get hashCode => Object.hash(id, customName);

  @override
  String toString() =>
      customName != null ? 'CardTag($id: $customName)' : 'CardTag($id)';
}
