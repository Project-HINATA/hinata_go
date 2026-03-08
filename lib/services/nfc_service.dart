import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import '../constants/mifare_key.dart';
import '../models/card/scanned_card.dart';
import '../models/card/aic.dart';
import '../models/card/aime.dart';
import '../models/card/banapass.dart';
import '../models/card/felica.dart';
import '../models/card/iso14443a.dart';
import '../utils/spad0.dart';

Uint8List _toUint8List(String hexString) {
  return Uint8List.fromList(hex.decode(hexString));
}

String _toHex(Uint8List bytes) {
  return hex.encode(bytes).toUpperCase();
}

Future<ScannedCard?> handleNfcTag(NFCTag tag) async {
  // Try Felica
  if (tag.type == NFCTagType.iso18092) {
    return await _handleFelica(tag);
  }

  // Try Mifare Classic / ISO14443-4
  if (tag.type == NFCTagType.mifare_classic ||
      tag.type == NFCTagType.mifare_ultralight ||
      tag.type == NFCTagType.iso7816) {
    return await _handleMifareClassic(tag);
  }

  return null;
}

Future<Uint8List> _felicaReadWithoutEncryption(
  Uint8List idm,
  List<int> blocks, {
  int serviceCode = 0x000B,
}) async {
  final command = BytesBuilder();

  command.addByte(0);
  command.addByte(0x06);
  command.add(idm);

  command.addByte(1);

  command.addByte(serviceCode & 0xFF);
  command.addByte((serviceCode >> 8) & 0xFF);
  command.addByte(blocks.length);

  for (var block in blocks) {
    command.addByte(0x80);
    command.addByte(block & 0xFF);
  }

  Uint8List fullPayload = command.toBytes();
  fullPayload[0] = fullPayload.length;

  final responseHex = await FlutterNfcKit.transceive(_toHex(fullPayload));
  return _toUint8List(responseHex);
}

bool _mayAic(Uint8List idm, Uint8List pmm, Uint16List systemCodes) {
  if (idm.length < 2 || pmm.length < 8) return false;
  return idm[0] == 0x01 &&
      idm[1] == 0x2E &&
      pmm[0] == 0x00 &&
      pmm[1] == 0xF1 &&
      pmm[2] == 0x00 &&
      pmm[3] == 0x00 &&
      pmm[4] == 0x00 &&
      pmm[5] == 0x01 &&
      pmm[6] == 0x43 &&
      pmm[7] == 0x00 &&
      (systemCodes.isEmpty || systemCodes[0] == 0x88B4 || systemCodes[0] == 0);
}

Future<ScannedCard?> _handleFelica(NFCTag tag) async {
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

  log('Felica System Codes: ${systemCodes.join(', ')}');

  final felica = Felica(idm, pmm, systemCodes);
  final defaultReturn = ScannedCard(card: felica, source: 'NFC');

  // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
  if ((idm[0] & 0xF0) != 0x00) {
    return defaultReturn;
  }

  // 2. Check PMm and IDm specific bytes for Amusement IC
  final mayAic = _mayAic(idm, pmm, systemCodes);
  if (!mayAic) {
    return defaultReturn;
  }

  try {
    final response = await _felicaReadWithoutEncryption(idm, [0]);

    // Check response length (minimum 13 bytes to contain Status Flags)
    if (response.length < 12) {
      return null;
    }

    final blockData = response.sublist(13, 13 + 16);

    if (blockData.every((byte) => byte == 0)) {
      return defaultReturn;
    }

    // Decrypt block using spad0
    final dec = spad0Decrypt(blockData);

    // Validate Amusement IC format
    if (dec[5] != 0) {
      return defaultReturn;
    }

    // Checking high 4 bits of 7th byte for 0x50 (AIC_HEADER_VALID)
    if ((dec[6] & 0xF0) == 0x50) {
      final accessCodeBytes = Uint8List.fromList(dec.sublist(6, 16));
      final aic = felica.toAic(accessCodeBytes);
      return ScannedCard(card: aic, source: 'NFC');
    }
  } catch (e) {
    log('Felica read error: $e');
  }
  return null;
}

Future<ScannedCard?> _handleMifareClassic(NFCTag tag) async {
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

  try {
    // Banapassort: Block 1 & 2 authenticated with Auth A
    try {
      await FlutterNfcKit.authenticateSector(
        0,
        keyA: Uint8List.fromList(banaKey),
      );

      final block1 = await FlutterNfcKit.readBlock(1);
      final block2 = await FlutterNfcKit.readBlock(2);

      final iso = Iso14443(id, sak, atqaInt);
      final banapass = iso.toBanapass(block1, block2);
      return ScannedCard(card: banapass, source: 'NFC');
    } catch (_) {}

    // Aime: Block 2 authenticated with Auth B
    try {
      await FlutterNfcKit.authenticateSector(
        0,
        keyB: Uint8List.fromList(aimeKey),
      );

      final block2 = await FlutterNfcKit.readBlock(2);
      if (block2.length >= 16) {
        final accessCodeBytes = Uint8List.fromList(block2.sublist(6, 16));
        final iso = Iso14443(id, sak, atqaInt);
        final aime = iso.toAime(accessCodeBytes);
        return ScannedCard(card: aime, source: 'NFC');
      }
    } catch (_) {}
  } catch (e) {
    log('Mifare error: $e');
  }
  return null;
}
