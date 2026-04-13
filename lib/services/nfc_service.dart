import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../models/card/scanned_card.dart';
import '../utils/nfc_tag_converter.dart';
import 'nfc/card_reader_engine.dart';
import 'nfc/native_nfc_transceiver.dart';

Future<ScannedCard?> handleNfcTag(NFCTag tag) async {
  final engine = CardReaderEngine(NativeNfcTransceiver());
  final internalTag = tag.toInternalTag();

  if (internalTag == null) return null;

  return await engine.processTag(internalTag, source: 'NFC');
}
