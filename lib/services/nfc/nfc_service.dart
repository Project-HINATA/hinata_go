import 'dart:developer';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

import '../../models/card/card_read_result.dart';
import '../../models/card/scanned_card.dart';
import '../../core/engine/nfc_tag_converter.dart';
import '../../core/engine/card_reader_engine.dart';
import 'phone_ndef_service.dart';

Future<CardReadResult> handleNfcTag(
  NFCTag tag, {
  bool readExtended = true,
  ScannedCard? existingCard,
  void Function(ScannedCard card)? onProgress,
}) async {
  if (tag.ndefAvailable == true) {
    try {
      return CardReadResult.recognized(
        ScannedCard(card: await readPhoneNdef(tag), source: 'NFC'),
      );
    } catch (error, stackTrace) {
      log('NDEF read incomplete', error: error, stackTrace: stackTrace);
      return const CardReadResult.incomplete();
    }
  }
  final channel = PhoneNfcCardChannel();
  final engine = CardReaderEngine(channel);
  final internalTag = tag.toInternalTag();

  if (internalTag == null) return const CardReadResult.noTarget();

  return await engine.processTag(
    internalTag,
    source: 'NFC',
    readExtended: readExtended,
    existingCard: existingCard,
    onProgress: onProgress,
  );
}
