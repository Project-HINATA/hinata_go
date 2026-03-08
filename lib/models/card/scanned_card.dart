import 'card.dart';
import 'aic.dart';
import 'aime.dart';
import 'felica.dart';

/// Wrapper around [ICCard] representing a card that was just scanned/read.
/// Replaces the old `ParsedCard`.
class ScannedCard {
  final ICCard card;
  final String source; // 'NFC', 'QR', 'Direct'

  const ScannedCard({required this.card, required this.source});

  /// User-facing display value based on card type.
  String get showValue {
    if (card is Aic) return (card as Aic).accessCodeString;
    if (card is Aime) return (card as Aime).accessCodeString;
    if (card is Felica) return (card as Felica).idString;
    // Banapass and others: just show the card name
    return card.name;
  }
}
