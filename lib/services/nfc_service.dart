import 'package:hinata_card_io/hinata_card_io.dart';

import '../models/card/scanned_card.dart';
import 'nfc/card_reader_engine.dart';

Future<ScannedCard?> handleNfcPollResult(PhoneNfcPollResult pollResult) async {
  final engine = CardReaderEngine(pollResult.transceiver);

  return await engine.processTag(pollResult.tag, source: 'NFC');
}
