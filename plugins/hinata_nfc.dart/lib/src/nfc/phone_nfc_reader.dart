import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';

import 'target.dart';
import 'phone_nfc_card_channel.dart';

class PhoneNfcReader {
  static Future<bool> isAvailable() async {
    NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
    return availability == NFCAvailability.available;
  }

  static Future<NfcTarget?> poll({
    String iosAlertMessage = "Hold your card near the top of your iPhone",
    bool readIso18092 = true,
    bool readIso14443B = false,
    bool readIso15693 = true,
  }) async {
    NFCTag tag = await FlutterNfcKit.poll(
      iosAlertMessage: iosAlertMessage,
      readIso18092: readIso18092,
      readIso14443B: readIso14443B,
      readIso15693: readIso15693,
    );

    return _toNfcTarget(tag);
  }

  static Future<void> finish() async {
    await FlutterNfcKit.finish();
  }

  static PhoneNfcCardChannel getCardChannel() {
    return PhoneNfcCardChannel();
  }

  static NfcTarget? _toNfcTarget(NFCTag tag) {
    final idBytes = Uint8List.fromList(hex.decode(tag.id));
    if (tag.type == NFCTagType.iso18092) {
      Uint8List pmm = Uint8List(8);
      Uint16List systemCodes = Uint16List(0);

      if (tag.manufacturer != null && tag.manufacturer!.isNotEmpty) {
        pmm = Uint8List.fromList(hex.decode(tag.manufacturer!));
      }

      if (tag.systemCode != null && tag.systemCode!.isNotEmpty) {
        final systemCodesU8 = Uint8List.fromList(hex.decode(tag.systemCode!));
        systemCodes = Uint16List.fromList(
          Iterable.generate(systemCodesU8.length ~/ 2, (i) {
            return (systemCodesU8[i * 2] << 8) | systemCodesU8[i * 2 + 1];
          }).toList(),
        );
      }
      return NfcTarget(id: idBytes, pmm: pmm, systemCodes: systemCodes);
    }

    if (tag.type == NFCTagType.iso15693) {
      if (idBytes.isNotEmpty) {
        return NfcTarget(id: idBytes);
      }
    }

    if (tag.type == NFCTagType.mifare_classic ||
        tag.type == NFCTagType.mifare_ultralight ||
        tag.type == NFCTagType.iso7816) {
      int sakInt = 0x08;
      int atqaInt = 0x0400;

      if (tag.sak != null && tag.sak!.isNotEmpty) {
        sakInt = int.tryParse(tag.sak!, radix: 16) ?? 0x08;
      }
      if (tag.atqa != null && tag.atqa!.isNotEmpty) {
        final atqaBytes = Uint8List.fromList(hex.decode(tag.atqa!));
        if (atqaBytes.length >= 2) {
          atqaInt = (atqaBytes[1] << 8) | atqaBytes[0];
        }
      }
      return NfcTarget(id: idBytes, sak: sakInt, atqa: atqaInt);
    }

    return null;
  }
}
