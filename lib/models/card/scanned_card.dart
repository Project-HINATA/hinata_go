import 'card.dart';
import 'aic.dart';
import 'aime.dart';
import 'felica.dart';
import 'iso15693.dart';

/// Wrapper around [ICCard] representing a card that was just scanned/read.
/// Replaces the old `ParsedCard`.
class ScannedCard {
  final ICCard card;
  final String source; // 'NFC', 'QR', 'Direct'
  final DateTime timestamp;

  ScannedCard({required this.card, required this.source, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// User-facing display value based on card type.
  String get showValue {
    if (card is Aic) return (card as Aic).accessCodeString;
    if (card is Aime) return (card as Aime).accessCodeString;
    if (card is Felica) return (card as Felica).idString;
    if (card is Iso15693) return (card as Iso15693).idString;
    // Banapass and others: just show the card name
    return card.name;
  }
}
