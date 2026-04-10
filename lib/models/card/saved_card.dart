import 'card.dart';
import 'aic.dart';
import 'aime.dart';
import 'banapass.dart';
import 'felica.dart';
import 'iso15693.dart';
import 'scanned_card.dart';

/// Persisted card model wrapping an [ICCard]. Replaces the old `BagCard`.
class SavedCard {
  final String id;
  final String name;
  final ICCard card;
  final String folderId;
  final String source;

  SavedCard({
    required this.id,
    required this.name,
    required this.card,
    required this.folderId,
    this.source = 'Direct',
  });

  /// User-facing display value based on card type.
  String get showValue {
    if (card is Aic) return (card as Aic).accessCodeString;
    if (card is Aime) return (card as Aime).accessCodeString;
    if (card is Felica) return (card as Felica).idString;
    if (card is Banapass) {
      return (card as Banapass).accessCodeString ?? card.name;
    }
    if (card is Iso15693) return (card as Iso15693).idString;
    return card.name;
  }

  /// Create a [SavedCard] from a [ScannedCard].
  factory SavedCard.fromScanned(
    ScannedCard scanned, {
    required String id,
    required String folderId,
    String? name,
  }) {
    return SavedCard(
      id: id,
      name: name ?? scanned.card.name,
      card: scanned.card,
      folderId: folderId,
      source: scanned.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'card': card.toJson(),
      'folderId': folderId,
      'source': source,
    };
  }

  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: json['id'] as String,
      name: json['name'] as String,
      card: ICCard.fromJson(json['card'] as Map<String, dynamic>),
      folderId: json['folderId'] as String,
      source: json['source'] as String? ?? 'Direct',
    );
  }

  SavedCard copyWith({
    String? id,
    String? name,
    ICCard? card,
    String? folderId,
    String? source,
  }) {
    return SavedCard(
      id: id ?? this.id,
      name: name ?? this.name,
      card: card ?? this.card,
      folderId: folderId ?? this.folderId,
      source: source ?? this.source,
    );
  }
}
