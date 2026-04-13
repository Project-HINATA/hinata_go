import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';

import '../models/card/felica.dart';
import '../models/card/iso14443a.dart';
import '../models/card/iso15693.dart';

Uint8List _toUint8List(String hexString) {
  return Uint8List.fromList(hex.decode(hexString));
}

extension NfcTagConverter on NFCTag {
  /// Converts flutter_nfc_kit's string-based tag representation to internal binary tag models.
  dynamic toInternalTag() {
    if (type == NFCTagType.iso18092) {
      final idm = _toUint8List(id);
      Uint8List pmm = Uint8List(8);
      Uint16List systemCodes = Uint16List(0);

      if (manufacturer != null && manufacturer!.isNotEmpty) {
        pmm = _toUint8List(manufacturer!);
      }

      if (systemCode != null && systemCode!.isNotEmpty) {
        final systemCodesU8 = _toUint8List(systemCode!);
        systemCodes = Uint16List.fromList(
          Iterable.generate(systemCodesU8.length ~/ 2, (i) {
            return (systemCodesU8[i * 2] << 8) | systemCodesU8[i * 2 + 1];
          }).toList(),
        );
      }
      return Felica(idm, pmm, systemCodes);
    }

    if (type == NFCTagType.iso15693) {
      final uid = _toUint8List(id);
      if (uid.isNotEmpty) {
        return Iso15693(uid);
      }
    }

    if (type == NFCTagType.mifare_classic ||
        type == NFCTagType.mifare_ultralight ||
        type == NFCTagType.iso7816) {
      final uid = _toUint8List(id);
      int sakInt = 0x08;
      int atqaInt = 0x0400;

      if (sak != null && sak!.isNotEmpty) {
        sakInt = int.tryParse(sak!, radix: 16) ?? 0x08;
      }
      if (atqa != null && atqa!.isNotEmpty) {
        final atqaBytes = _toUint8List(atqa!);
        if (atqaBytes.length >= 2) {
          atqaInt = (atqaBytes[1] << 8) | atqaBytes[0];
        }
      }
      return Iso14443(uid, sakInt, atqaInt);
    }

    return null;
  }
}
