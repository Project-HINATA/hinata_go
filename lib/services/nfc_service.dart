import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

import '../models/card/scanned_card.dart';
import '../utils/nfc_tag_converter.dart';
import 'nfc/card_reader_engine.dart';

Future<ScannedCard?> handleNfcTag(
  NFCTag tag, {
  bool readExtended = true,
}) async {
  final channel = PhoneNfcCardChannel();
  final engine = CardReaderEngine(channel);
  final internalTag = tag.toInternalTag();

  if (internalTag == null) return null;

  return await engine.processTag(
    internalTag,
    source: 'NFC',
    readExtended: readExtended,
  );
}
