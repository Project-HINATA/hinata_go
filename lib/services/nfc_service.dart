import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../constants/mifare_key.dart';
import '../utils/spad0.dart';

String _toHexString(Uint8List bytes) {
  return bytes
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
}

String _extractAccessCode(Uint8List slice) {
  if (slice.length != 10) return _toHexString(slice);
  return _toHexString(slice);
}

Future<(String type, String value)?> handleNfcTag(NfcTag tag) async {
  // Try Felica
  final nfcf = NfcFAndroid.from(tag);
  if (nfcf != null) {
    return await _handleFelica(nfcf);
  }

  // Try Mifare Classic (Android only)
  final mifare = MifareClassicAndroid.from(tag);
  if (mifare != null) {
    return await _handleMifareClassic(mifare);
  }

  // Fallback generic check
  final androidTag = NfcTagAndroid.from(tag);
  final idArray = androidTag?.id ?? Uint8List(0);
  final uid = _toHexString(idArray);
  return ('Unknown', uid);
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

Future<(String, String)> _handleFelica(NfcFAndroid nfcf) async {
  final idm = nfcf.tag.id;
  final defaultReturn = ('Felica', _toHexString(idm));

  // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
  if ((idm[0] & 0xF0) != 0x00) {
    return defaultReturn;
  }

  // 2. Check PMm and IDm specific bytes for Amusement IC
  if (!_mayAic(idm, nfcf.manufacturer)) {
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

    // Check response length (minimum 13 bytes to contain Status Flags)
    if (response.length < 12) {
      return defaultReturn;
    }

    // Android NfcF transceive might or might not return the length SoD byte.
    // However, typical payload: [Response Code 0x07], [IDm 8 bytes], [Status Flag 1], [Status Flag 2], etc.
    int offset = 0;
    if (response[0] == 0x07) {
      offset = 0;
    } else if (response.length > 1 && response[1] == 0x07) {
      offset = 1;
    } else {
      return defaultReturn;
    }

    final sf1 = response[offset + 9];
    final sf2 = response[offset + 10];
    if (sf1 != 0x00 || sf2 != 0x00) {
      return defaultReturn;
    }

    // Extract exactly 16 bytes of block data starting from offset + 12
    if (response.length < offset + 28) return defaultReturn;
    final blockData = response.sublist(offset + 12, offset + 28);

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
      final accessCodeBytes = dec.sublist(6, 16);
      return ('Amusement IC', _extractAccessCode(accessCodeBytes));
    }
  } catch (e) {
    // Ignore and fallback to generic Felica
  }

  return defaultReturn;
}

Future<(String, String)> _handleMifareClassic(
  MifareClassicAndroid mifare,
) async {
  final uid = _toHexString(mifare.tag.id);

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

        final data = BytesBuilder();
        data.add(block1);
        data.add(block2);

        return ('Banapass', _toHexString(data.toBytes()));
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
          final accessCodeBytes = block2.sublist(6, 16);
          return ('Aime', _extractAccessCode(accessCodeBytes));
        }
      }
    } catch (_) {}
  } catch (e) {
    // Fallback to uid
  }

  return ('Mifare Classic', uid);
}
