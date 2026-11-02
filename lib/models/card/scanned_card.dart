import 'card.dart';
import 'felica.dart';
import 'transit.dart';

/// Wrapper around [ICCard] representing a card that was just scanned/read.
/// Replaces the old `ParsedCard`.
class ScannedCard {
  final ICCard card;
  final String source; // 'NFC', 'QR', 'Direct'
  final DateTime timestamp;
  final bool isExtendedInfoFullyLoaded;
  final bool isUsable;

  ScannedCard({
    required this.card,
    required this.source,
    DateTime? timestamp,
    this.isExtendedInfoFullyLoaded = false,
    this.isUsable = true,
  }) : timestamp = timestamp ?? DateTime.now();

  /// User-facing display value based on card type.
  String get showValue => card.showedValue;

  /// Whether the card has more to read after it is first shown: a transit
  /// card's history, or a FeliCa card's blocks.
  bool get hasExtendedInfo => card is TransitCard || card is Felica;
}
