import 'dart:developer';
import 'dart:typed_data';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import '../../utils/spad0.dart';
import '../../constants/mifare_key.dart';
import 'nfc_transceiver.dart';
import 'nfc_exception.dart';

class CardReaderEngine {
  final NfcTransceiver transceiver;

  CardReaderEngine(this.transceiver);

  /// Standard AIC Service Code for Reading
  static const int aicServiceCode = 0x000B;

  /// High-level logic for handling FeliCa tags (AIC Detection)
  Future<ScannedCard?> handleFelica({
    required Felica tag,
    String source = 'NFC',
  }) async {
    log(tag.id.toString());
    final defaultReturn = ScannedCard(card: tag, source: source);

    // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
    if ((tag.id[0] & 0xF0) != 0x00) {
      return defaultReturn;
    }

    // 2. Check PMm and IDm specific bytes for Amusement IC
    if (!_mayAic(tag.id, tag.pmm, tag.systemCode)) {
      return defaultReturn;
    }

    try {
      final response = await felicaReadWithoutEncryption(tag.id, [0]);

      // Check response length (minimum 13 bytes to contain Status Flags)
      if (response.length < 12) {
        return null; // Unexpected response format
      }

      final blockData = response.sublist(13, 13 + 16);

      if (blockData.every((byte) => byte == 0)) {
        return defaultReturn;
      }

      // Decrypt block using spad0
      final dec = spad0Decrypt(blockData);

      // Validate Amusement IC format (5th byte must be 0)
      if (dec[5] != 0) {
        return defaultReturn;
      }

      // Checking high 4 bits of 7th byte for 0x50 (AIC Header)
      final prefix = dec[6] & 0xF0;
      if (prefix == 0x50) {
        final accessCodeBytes = Uint8List.fromList(dec.sublist(6, 16));
        final aic = tag.toAic(accessCodeBytes);
        return ScannedCard(card: aic, source: source);
      }
    } catch (e) {
      log('CardReaderEngine Felica error: $e');
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'Failed to read FeliCa data',
        originalError: e,
      );
    }
    return defaultReturn;
  }

  Future<ScannedCard?> handleBana({
    required Iso14443 tag,
    String source = 'NFC',
  }) async {
    try {
      await transceiver.authenticateMifare(
        uid: tag.id,
        block: 1, // Sector 0
        keyA: Uint8List.fromList(banaKey),
      );

      final block1 = await transceiver.readMifareBlock(1);
      final block2 = await transceiver.readMifareBlock(2);

      final banapass = tag.toBanapass(
        Uint8List.fromList(block1),
        Uint8List.fromList(block2),
      );
      return ScannedCard(card: banapass, source: source);
    } catch (_) {
      return null;
    }
  }

  Future<ScannedCard?> handleAime({
    required Iso14443 tag,
    String source = 'NFC',
  }) async {
    try {
      await transceiver.authenticateMifare(
        uid: tag.id,
        block: 2, // Sector 0
        keyB: Uint8List.fromList(aimeKey),
      );

      final block2 = await transceiver.readMifareBlock(2);
      if (block2.length >= 16) {
        final accessCodeBytes = Uint8List.fromList(block2.sublist(6, 16));
        final aime = tag.toAime(accessCodeBytes);
        return ScannedCard(card: aime, source: source);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Helper for FeliCa Read Without Encryption logic
  Future<Uint8List> felicaReadWithoutEncryption(
    Uint8List idm,
    List<int> blocks, {
    int serviceCode = aicServiceCode,
  }) async {
    final command = BytesBuilder();

    command.addByte(0); // Placeholder for length
    command.addByte(0x06); // FeliCa Read Without Encryption Command
    command.add(idm);

    command.addByte(1); // One service

    command.addByte(serviceCode & 0xFF);
    command.addByte((serviceCode >> 8) & 0xFF);
    command.addByte(blocks.length);

    for (var block in blocks) {
      command.addByte(0x80); // Block list element (2-byte, 1-byte addr)
      command.addByte(block & 0xFF);
    }

    Uint8List fullPayload = command.toBytes();
    fullPayload[0] = fullPayload.length;

    return await transceiver.transceive(fullPayload);
  }

  /// AIC potential check
  bool _mayAic(Uint8List idm, Uint8List pmm, Uint16List systemCodes) {
    if (idm.length < 2 || pmm.length < 8) return false;
    // Standard SEGA/AIC fingerprinting logic
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
        (systemCodes.isEmpty ||
            systemCodes[0] == 0x88B4 ||
            systemCodes[0] == 0);
  }

  /// Unified entry point for resolving a tag
  Future<ScannedCard?> processTag(dynamic rawTag, {String source = 'NFC'}) async {
    if (rawTag is Felica) {
      return await handleFelica(tag: rawTag, source: source);
    } 
    
    if (rawTag is Iso14443) {
      // Try Bana first
      var scanned = await handleBana(tag: rawTag, source: source);
      if (scanned != null) return scanned;

      // Reactivate card (vital for PN532 as failure to auth halts the card)
      await transceiver.reconnect();

      // Try Aime
      scanned = await handleAime(tag: rawTag, source: source);
      return scanned;
    }

    // Pass through Iso15693 or any other generic parsed tags
    if (rawTag is Iso15693) {
      return ScannedCard(card: rawTag, source: source);
    }

    return null;
  }
}

