import 'dart:developer';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../constants/mifare_key.dart';
import '../models/card/scanned_card.dart';
import '../models/card/aic.dart';
import '../models/card/aime.dart';
import '../models/card/banapass.dart';
import '../models/card/felica.dart';
import '../models/card/iso14443a.dart';
import '../utils/spad0.dart';

String _toHexString(Uint8List bytes) {
  return bytes
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
}

Future<ScannedCard?> handleNfcTag(NfcTag tag) async {
  // Try Felica
  final nfcf = NfcFAndroid.from(tag);
  if (nfcf != null) {
    return await _handleFelica(nfcf);
  }

  // Try Mifare Classic (Android only)
  final mifare = MifareClassicAndroid.from(tag);
  if (mifare != null) {
    return await _handleMifareClassic(mifare, tag);
  }

  return null;
}

Future<Uint8List> _felicaReadWithoutEncryption(
  NfcFAndroid nfcf,
  Uint8List idm, {
  required int serviceCode,
  required int block,
}) async {
  final command = BytesBuilder();
  command.addByte(0);
  command.addByte(0x06); // Command Code
  command.add(idm); // IDm (8 bytes)
  command.addByte(0x01); // Number of Services
  command.add([
    serviceCode & 0xFF,
    (serviceCode >> 8) & 0xFF,
  ]); // Service Code List (Little Endian)
  command.addByte(0x01); // Number of Blocks
  command.add([
    0x80,
    block & 0xFF,
  ]); // Block List Element (2-byte block list element)

  return await nfcf.transceive(command.toBytes());
}

bool _mayAic(Uint8List idm, Uint8List pmm) {
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
      pmm[7] == 0x00;
}

Future<ScannedCard?> _handleFelica(NfcFAndroid nfcf) async {
  final idm = nfcf.tag.id;
  final pmm = nfcf.manufacturer;
  final felica = Felica(idm, pmm, Uint16List(0));

  final defaultReturn = ScannedCard(card: felica, source: 'NFC');

  // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
  if ((idm[0] & 0xF0) != 0x00) {
    return defaultReturn;
  }

  // 2. Check PMm and IDm specific bytes for Amusement IC
  final mayAic = _mayAic(idm, pmm);
  if (!mayAic) {
    return defaultReturn;
  }

  try {
    // 3. Try reading Amusement IC data area
    final response = await _felicaReadWithoutEncryption(
      nfcf,
      idm,
      serviceCode: 0x000B,
      block: 0,
    );

    log(_toHexString(response));

    // Check response length (minimum 13 bytes to contain Status Flags)
    if (response.length < 12) {
      return null;
    }

    final blockData = response.sublist(13, 13 + 16);

    // Decrypt block using spad0
    final dec = spad0Decrypt(blockData);

    // Validate Amusement IC format
    bool isZeros = true;
    for (int i = 0; i < 6; i++) {
      if (dec[i] != 0) {
        isZeros = false;
        break;
      }
    }

    // Checking high 4 bits of 7th byte for 0x50 (AIC_HEADER_VALID)
    if (isZeros && (dec[6] & 0xF0) == 0x50) {
      final accessCodeBytes = Uint8List.fromList(dec.sublist(6, 16));
      final aic = felica.toAic(accessCodeBytes);
      return ScannedCard(card: aic, source: 'NFC');
    }
  } catch (e) {
    // Ignore and fallback to generic Felica
  }
  return null;
}

Future<ScannedCard> _handleMifareClassic(
  MifareClassicAndroid mifare,
  NfcTag nfcTag,
) async {
  final id = mifare.tag.id;
  final nfcA = NfcAAndroid.from(nfcTag);
  final sak = nfcA?.sak ?? 0x08;
  final atqa = nfcA?.atqa ?? Uint8List.fromList([0x04, 0x00]);
  final atqaInt = (atqa[1] << 8) | atqa[0];

  try {
    // Banapassort: Block 1 & 2 authenticated with Auth A
    try {
      bool authBana = await mifare.authenticateSectorWithKeyA(
        sectorIndex: 0,
        key: Uint8List.fromList(banaKey),
      );
      if (authBana) {
        final block1 = await mifare.readBlock(blockIndex: 1);
        final block2 = await mifare.readBlock(blockIndex: 2);

        final iso = Iso14443(id, sak, atqaInt);
        final banapass = iso.toBanapass(
          Uint8List.fromList(block1),
          Uint8List.fromList(block2),
        );
        return ScannedCard(card: banapass, source: 'NFC');
      }
    } catch (_) {}

    // Aime: Block 2 authenticated with Auth B
    try {
      bool authAime = await mifare.authenticateSectorWithKeyB(
        sectorIndex: 0,
        key: Uint8List.fromList(aimeKey),
      );
      if (authAime) {
        final block2 = await mifare.readBlock(blockIndex: 2);
        if (block2.length >= 16) {
          final accessCodeBytes = Uint8List.fromList(block2.sublist(6, 16));
          final iso = Iso14443(id, sak, atqaInt);
          final aime = iso.toAime(accessCodeBytes);
          return ScannedCard(card: aime, source: 'NFC');
        }
      }
    } catch (_) {}
  } catch (e) {
    // Fallback to generic
  }

  // Fallback: return as generic Felica-like with idString
  final iso = Iso14443(id, sak, atqaInt);
  return ScannedCard(card: iso, source: 'NFC');
}
