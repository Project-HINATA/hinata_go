import 'scanned_card.dart';

enum CardReadStatus { recognized, confirmedUnsupported, incomplete, noTarget }

class CardReadResult {
  final CardReadStatus status;
  final ScannedCard? card;

  const CardReadResult._(this.status, this.card);

  const CardReadResult.recognized(ScannedCard card)
    : this._(CardReadStatus.recognized, card);

  const CardReadResult.confirmedUnsupported(ScannedCard card)
    : this._(CardReadStatus.confirmedUnsupported, card);

  const CardReadResult.incomplete() : this._(CardReadStatus.incomplete, null);

  const CardReadResult.noTarget() : this._(CardReadStatus.noTarget, null);
}
