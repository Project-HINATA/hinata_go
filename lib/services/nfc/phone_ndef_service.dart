import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../../models/card/card.dart';
import '../../models/card/ndef.dart';
import '../../core/engine/nfc_tag_converter.dart';
import 'mifare_card_writer.dart';

Future<NdefCard> readPhoneNdef(NFCTag tag) async {
  final records = await FlutterNfcKit.readNDEFRawRecords(cached: false);
  final uid = tag.id == 'unknown' ? Uint8List(0) : ICCard.hexToBytes(tag.id);
  return NdefCard(
    ndef.encodeNdefMessage(
      records
          .map(
            (r) => ndef.NDEFRecord(
              tnf: r.typeNameFormat,
              id: r.identifier.isEmpty ? null : ICCard.hexToBytes(r.identifier),
              type: ICCard.hexToBytes(r.type),
              payload: ICCard.hexToBytes(r.payload),
            ),
          )
          .toList(),
    ),
    physicalCard: uid.isEmpty
        ? ICCard(uid)
        : tag.toInternalTag() as ICCard? ?? ICCard(uid),
    capacity: tag.ndefCapacity,
  );
}

/// Writes [card] through the system NDEF stack. With [readOnly] the tag is
/// then locked by the system, after the content has been verified; a tag the
/// system cannot lock is refused before anything is written.
Future<void> writePhoneNdef(
  NFCTag tag,
  NdefCard card, {
  required MifareWriteStageCallback onStage,
  required bool Function() isCancelled,
  bool readOnly = false,
}) async {
  onStage(MifareWriteStage.checkingPermissions);
  if (tag.ndefAvailable != true) {
    throw const MifareCardWriteException(
      MifareWriteFailure.unsupportedCard,
      'The system cannot format this tag as NDEF',
    );
  }
  if (tag.ndefWritable != true) {
    throw const MifareCardWriteException(
      MifareWriteFailure.permissionDenied,
      'NDEF tag is read-only',
    );
  }
  if (readOnly && tag.ndefCanMakeReadOnly != true) {
    throw const MifareCardWriteException(
      MifareWriteFailure.lockUnsupported,
      'The system cannot make this tag read-only',
    );
  }
  final encoded = ndef.encodeNdefMessage(card.records);
  if (tag.ndefCapacity == null || encoded.length > tag.ndefCapacity!) {
    throw const MifareCardWriteException(
      MifareWriteFailure.capacityExceeded,
      'Insufficient NDEF capacity',
    );
  }
  if (isCancelled()) {
    throw const MifareCardWriteException(
      MifareWriteFailure.cancelled,
      'Cancelled before writing',
    );
  }
  onStage(MifareWriteStage.writingData);
  await FlutterNfcKit.writeNDEFRawRecords(
    card.records
        .map(
          (r) => NDEFRawRecord(
            hex.encode(r.id ?? []),
            hex.encode(r.payload!),
            hex.encode(r.type!),
            r.tnf,
          ),
        )
        .toList(),
  );
  onStage(MifareWriteStage.verifying);
  if (!listEquals(encoded, (await readPhoneNdef(tag)).message)) {
    throw const MifareCardWriteException(
      MifareWriteFailure.verificationFailed,
      'NDEF read-back mismatch',
    );
  }
  if (!readOnly) return;

  onStage(MifareWriteStage.lockingCard);
  try {
    await FlutterNfcKit.makeNdefReadOnly();
  } catch (error) {
    throw MifareCardWriteException(
      MifareWriteFailure.writeFailed,
      'The system could not make the tag read-only',
      cause: error,
    );
  }
  onStage(MifareWriteStage.verifying);
  if (!listEquals(encoded, (await readPhoneNdef(tag)).message)) {
    throw const MifareCardWriteException(
      MifareWriteFailure.verificationFailed,
      'NDEF read-back mismatch after locking',
    );
  }
}
