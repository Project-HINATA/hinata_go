import 'card.dart';

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
}
