import 'card.dart';
import 'invalid_mifare.dart';

/// Wrapper around [ICCard] representing a card that was just scanned/read.
/// Replaces the old `ParsedCard`.
class ScannedCard {
  final ICCard card;
  final String source; // 'NFC', 'QR', 'Direct'
  final DateTime timestamp;
  final bool isExtendedInfoFullyLoaded;

  ScannedCard({
    required this.card,
    required this.source,
    DateTime? timestamp,
    this.isExtendedInfoFullyLoaded = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUsable => card is! InvalidMifareCard;

  /// User-facing display value based on card type.
  String get showValue => card.showedValue;
}
