import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import '../models/card/scanned_card.dart';
import '../models/card/iso15693.dart';
import 'nfc/card_reader_engine.dart';
import 'nfc/native_nfc_transceiver.dart';

Uint8List _toUint8List(String hexString) {
  return Uint8List.fromList(hex.decode(hexString));
}

Future<ScannedCard?> handleNfcTag(NFCTag tag) async {
  final engine = CardReaderEngine(NativeNfcTransceiver());

  // Try Felica
  if (tag.type == NFCTagType.iso18092) {
    final idm = _toUint8List(tag.id);
    Uint8List pmm = Uint8List(8);
    Uint16List systemCodes = Uint16List(0);

    if (tag.manufacturer != null && tag.manufacturer!.isNotEmpty) {
      pmm = _toUint8List(tag.manufacturer!);
    }

    if (tag.systemCode != null && tag.systemCode!.isNotEmpty) {
      final systemCodesU8 = _toUint8List(tag.systemCode!);
      systemCodes = Uint16List.fromList(
        Iterable.generate(systemCodesU8.length ~/ 2, (i) {
          return (systemCodesU8[i * 2] << 8) | systemCodesU8[i * 2 + 1];
        }).toList(),
      );
    }

    return await engine.handleFelica(tag: Felica(idm, pmm, systemCodes));
  }

  // Try ISO15693 (Directly handled as it doesn't need complex transceiver logic yet)
  if (tag.type == NFCTagType.iso15693) {
    final uid = _toUint8List(tag.id);
    if (uid.isNotEmpty) {
      return ScannedCard(card: Iso15693(uid), source: 'NFC');
    }
  }

  // Try Mifare Classic / ISO14443-A (Aime/Banapassport)
  if (tag.type == NFCTagType.mifare_classic ||
      tag.type == NFCTagType.mifare_ultralight ||
      tag.type == NFCTagType.iso7816) {
    final id = _toUint8List(tag.id);
    int sak = 0x08;
    int atqaInt = 0x0400;

    if (tag.sak != null && tag.sak!.isNotEmpty) {
      sak = int.tryParse(tag.sak!, radix: 16) ?? 0x08;
    }
    if (tag.atqa != null && tag.atqa!.isNotEmpty) {
      final atqaBytes = _toUint8List(tag.atqa!);
      if (atqaBytes.length >= 2) {
        atqaInt = (atqaBytes[1] << 8) | atqaBytes[0];
      }
    }
    final isoTag = Iso14443(id, sak, atqaInt);

    var res = await engine.handleBana(tag: isoTag);
    if (res != null) return res;
    res = await engine.handleAime(tag: isoTag);
    return res;
  }

  return null;
}
