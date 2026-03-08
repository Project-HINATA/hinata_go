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

// String _toHexString(Uint8List bytes) {
//   return bytes
//       .map((e) => e.toRadixString(16).padLeft(2, '0'))
//       .join('')
//       .toUpperCase();
// }

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

  return await nfcf.transceive(fullPayload);
}

Future _felicaPoll(NfcFAndroid nfcf) async {
  final command = BytesBuilder();
  command.addByte(0x06);
  command.addByte(0);
  command.addByte(0xFF);
  command.addByte(0xFF);
  command.addByte(1);
  command.addByte(0x0F);
  return await nfcf.transceive(command.toBytes());
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
      (systemCodes[0] == 0x88B4 || systemCodes[0] == 0);
}

Future<ScannedCard?> _handleFelica(NfcFAndroid nfcf) async {
  final idm = nfcf.tag.id;
  final pmm = nfcf.manufacturer;
  log(nfcf.systemCode.join(', '));

  final systemCodesU8 = nfcf.systemCode;
  final systemCodesU16 = Uint16List.fromList(
    Iterable.generate(systemCodesU8.length ~/ 2, (i) {
      return (systemCodesU8[i * 2] << 8) | systemCodesU8[i * 2 + 1];
    }).toList(),
  );

  final felica = Felica(idm, pmm, systemCodesU16);
  final defaultReturn = ScannedCard(card: felica, source: 'NFC');

  // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
  if ((idm[0] & 0xF0) != 0x00) {
    return defaultReturn;
  }

  // 2. Check PMm and IDm specific bytes for Amusement IC
  final mayAic = _mayAic(idm, pmm, systemCodesU16);
  if (!mayAic) {
    return defaultReturn;
  }

  try {
    _felicaPoll(nfcf); // NFC标签拉起应用时需要
    final response = await _felicaReadWithoutEncryption(nfcf, idm, [0]);

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
  } catch (_) {
    // If read error return null;
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
