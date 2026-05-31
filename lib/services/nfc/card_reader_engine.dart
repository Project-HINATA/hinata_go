import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/invalid_mifare.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/models/card/transit.dart';

import '../../constants/mifare_key.dart';
import '../../utils/access_code_validator.dart';
import '../../utils/spad0.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

class CardReaderEngine {
  final NfcCardChannel transceiver;

  CardReaderEngine(this.transceiver);

  /// Standard AIC Service Code for Reading
  static const int aicServiceCode = 0x000B;
  static const int _aimeAccessCodeStart = 6;
  static const int _aimeAccessCodeEnd = 16;

  /// High-level logic for handling FeliCa tags (AIC Detection)
  Future<ScannedCard?> handleFelica({
    required Felica tag,
    String source = 'NFC',
    bool readExtended = true,
  }) async {
    log(tag.id.toString());
    final defaultReturn = ScannedCard(card: tag, source: source);

    // 1. Quick filter: only process if IDm starts with 0x00 or 0x01
    if ((tag.id[0] & 0xF0) != 0x00) {
      return defaultReturn;
    }

    // 2. Check PMm and IDm specific bytes for Amusement IC
    if (!_mayAic(tag.id, tag.pmm, tag.systemCode)) {
      if (tag.systemCode.contains(0x0003)) {
        final suica = await _tryReadSuica(
          tag,
          source: source,
          readExtended: readExtended,
        );
        if (suica != null) return suica;
      }
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

  Future<ScannedCard?> readMifareWithBanaKey({
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
      if (AccessCodeValidator.isValidDecodedBanapassAccessCode(
        banapass.accessCodeString,
      )) {
        return ScannedCard(card: banapass, source: source);
      }

      return ScannedCard(
        card: tag.toInvalidMifareCard(
          unusableAccessCode: banapass.accessCodeString,
          block1: Uint8List.fromList(block1),
          block2: Uint8List.fromList(block2),
        ),
        source: source,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ScannedCard?> readMifareWithAimeKey({
    required Iso14443 tag,
    String source = 'NFC',
  }) async {
    await transceiver.authenticateMifare(
      uid: tag.id,
      block: 2, // Sector 0
      keyB: Uint8List.fromList(aimeKey),
    );

    final block2 = await transceiver.readMifareBlock(2);
    if (block2.length < _aimeAccessCodeEnd) {
      return ScannedCard(
        card: tag.toInvalidMifareCard(block2: Uint8List.fromList(block2)),
        source: source,
      );
    }

    final accessCodeBytes = Uint8List.fromList(
      block2.sublist(_aimeAccessCodeStart, _aimeAccessCodeEnd),
    );
    final aime = tag.toAime(accessCodeBytes);
    final aimeAccessCode = aime.accessCodeString;

    if (AccessCodeValidator.startsWithBanapassPrefix(aimeAccessCode)) {
      final banapass = await _readBanapassFromAimeAuthenticatedSector(
        tag: tag,
        block2: block2,
      );
      return banapass != null
          ? ScannedCard(card: banapass, source: source)
          : ScannedCard(
              card: tag.toInvalidMifareCard(
                unusableAccessCode: aimeAccessCode,
                block2: Uint8List.fromList(block2),
              ),
              source: source,
            );
    }

    if (!AccessCodeValidator.isValidAimeAccessCode(aimeAccessCode)) {
      return ScannedCard(
        card: tag.toInvalidMifareCard(
          unusableAccessCode: aimeAccessCode,
          block2: Uint8List.fromList(block2),
        ),
        source: source,
      );
    }

    return ScannedCard(card: aime, source: source);
  }

  Future<Banapass?> _readBanapassFromAimeAuthenticatedSector({
    required Iso14443 tag,
    required Uint8List block2,
  }) async {
    try {
      final block1 = await transceiver.readMifareBlock(1);
      final banapass = tag.toBanapass(
        Uint8List.fromList(block1),
        Uint8List.fromList(block2),
      );

      return AccessCodeValidator.isValidDecodedBanapassAccessCode(
            banapass.accessCodeString,
          )
          ? banapass
          : null;
    } catch (e, s) {
      log(
        'CardReaderEngine Banapass block1 decrypt error',
        error: e,
        stackTrace: s,
      );
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
  Future<ScannedCard?> processTag(
    dynamic rawTag, {
    String source = 'NFC',
    bool readExtended = true,
  }) async {
    if (rawTag is Felica) {
      return await handleFelica(
        tag: rawTag,
        source: source,
        readExtended: readExtended,
      );
    }

    if (rawTag is Iso14443) {
      // 1. Zero-cost SAK check: Only attempt T-Union if SAK indicates ISO14443-4 CPU card (bit 5)
      if ((rawTag.sak & 0x20) != 0) {
        final tunion = await _tryReadTUnion(
          rawTag,
          source: source,
          readExtended: readExtended,
        );
        if (tunion != null) {
          return tunion;
        }
      }

      if (!rawTag.isMifareClassicCandidate) {
        return ScannedCard(
          card: rawTag.toInvalidMifareCard(
            reason: InvalidMifareReason.invalidData,
          ),
          source: source,
        );
      }

      try {
        return await readMifareWithAimeKey(tag: rawTag, source: source);
      } on NfcException catch (e) {
        if (e.type != NfcErrorType.authFailed) {
          rethrow;
        }
      }

      // Reactivate card (vital for PN532 as failure to auth halts the card).
      await transceiver.reconnect();
      final scanned = await readMifareWithBanaKey(tag: rawTag, source: source);
      return scanned ??
          ScannedCard(
            card: rawTag.toInvalidMifareCard(
              reason: InvalidMifareReason.readFailure,
            ),
            source: source,
          );
    }

    // Pass through Iso15693 or any other generic parsed tags
    if (rawTag is Iso15693) {
      return ScannedCard(card: rawTag, source: source);
    }

    return null;
  }

  Future<ScannedCard?> _tryReadSuica(
    Felica tag, {
    required String source,
    bool readExtended = true,
  }) async {
    try {
      final List<Uint8List> blocksData = [];
      final List<double> blockBalances = [];
      double balance = 0.0;

      // Suica history service code is 0x090F
      const int suicaServiceCode = 0x090F;

      final int blocksToRead = readExtended ? 20 : 1;
      for (int blockIndex = 0; blockIndex < blocksToRead; blockIndex++) {
        // Read block using FeliCa Read Without Encryption
        final response = await felicaReadWithoutEncryption(tag.id, [
          blockIndex,
        ], serviceCode: suicaServiceCode);

        // Response should contain length, response code, IDm, status flags, block count, block data
        // status flags are at index 10 and 11, block data starts at index 13
        if (response.length < 29) {
          break; // Response too short or read finished
        }

        final status1 = response[10];
        final status2 = response[11];
        if (status1 != 0 || status2 != 0) {
          break; // Non-zero status flags indicate end of records or error
        }

        final blockData = response.sublist(13, 29);

        // Filter out empty transaction records (all zeros or all 0xFF, common on new cards)
        if (blockData.every((b) => b == 0 || b == 0xFF)) {
          continue;
        }

        // Bytes 13-14: Sequence Number (big-endian)
        final seq = (blockData[13] << 8) | blockData[14];

        // Filter out empty transaction records (sequence number is 0)
        if (seq == 0) {
          continue;
        }

        // Bytes 10-11: Balance (stored in little-endian order)
        final blockBalance = blockData[10] | (blockData[11] << 8);

        if (blockIndex == 0) {
          balance = blockBalance.toDouble();
        }

        blocksData.add(blockData);
        blockBalances.add(blockBalance.toDouble());
      }

      final List<TransitTransaction> transactions = [];
      for (int i = 0; i < blocksData.length; i++) {
        double amt = 0.0;
        if (i + 1 < blockBalances.length) {
          amt = blockBalances[i] - blockBalances[i + 1];
        }

        final tx = Suica.parseTransaction(blocksData[i], amt);
        transactions.add(tx);
      }

      final suica = Suica(
        tag.id,
        tag.pmm,
        tag.systemCode,
        balance: balance,
        transactions: transactions,
        snapshotTime: DateTime.now(),
      );

      return ScannedCard(card: suica, source: source);
    } catch (e) {
      log('CardReaderEngine Suica read error: $e');
      return null;
    }
  }

  /// Try to read ISO14443-4 T-Union card info, balance, and transaction history
  Future<ScannedCard?> _tryReadTUnion(
    Iso14443 tag, {
    required String source,
    bool readExtended = true,
  }) async {
    debugPrint('[_tryReadTUnion] Starting read. readExtended: $readExtended');
    try {
      // 1. SELECT China T-Union electronic purse application
      final selectAid = Uint8List.fromList([
        0x00,
        0xA4,
        0x04,
        0x00,
        0x08,
        0xA0,
        0x00,
        0x00,
        0x06,
        0x32,
        0x01,
        0x01,
        0x05,
      ]);
      final selectRes = await transceiver.transceive(selectAid);
      debugPrint(
        '[_tryReadTUnion] SELECT AID response length: ${selectRes.length}',
      );
      if (selectRes.length < 2) {
        debugPrint(
          '[_tryReadTUnion] SELECT AID response too short: ${selectRes.length}',
        );
        return null;
      }

      final sw1 = selectRes[selectRes.length - 2];
      final sw2 = selectRes[selectRes.length - 1];
      debugPrint(
        '[_tryReadTUnion] SELECT AID SW: ${sw1.toRadixString(16).toUpperCase()}${sw2.toRadixString(16).toUpperCase()}',
      );
      if (sw1 != 0x90 || sw2 != 0x00) {
        debugPrint(
          '[_tryReadTUnion] Not a China T-Union card (SELECT SW != 9000)',
        );
        return null;
      }

      // 2. READ CARD BASIC INFO: SFI 0x15
      final readInfo = Uint8List.fromList([0x00, 0xB0, 0x95, 0x00, 0x1E]);
      final infoRes = await transceiver.transceive(readInfo);
      debugPrint(
        '[_tryReadTUnion] READ INFO response length: ${infoRes.length}',
      );
      if (infoRes.length < 32) {
        debugPrint(
          '[_tryReadTUnion] READ INFO response too short: ${infoRes.length}',
        );
        return null;
      }

      final infoSw1 = infoRes[infoRes.length - 2];
      final infoSw2 = infoRes[infoRes.length - 1];
      if (infoSw1 != 0x90 || infoSw2 != 0x00) {
        debugPrint('[_tryReadTUnion] READ INFO SW != 9000');
        return null;
      }

      // Extract Application Serial Number (bytes 10 to 19 of payload)
      final asnBytes = infoRes.sublist(10, 20);
      final rawAsnStr = asnBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final cardNumber = rawAsnStr.startsWith('0')
          ? rawAsnStr.substring(1)
          : rawAsnStr;
      debugPrint('[_tryReadTUnion] parsed card number: $cardNumber');

      // 3. READ BALANCE: APDU 80 5C 00 02 04
      final readBal = Uint8List.fromList([0x80, 0x5C, 0x00, 0x02, 0x04]);
      final balRes = await transceiver.transceive(readBal);
      debugPrint(
        '[_tryReadTUnion] READ BALANCE response length: ${balRes.length}',
      );
      if (balRes.length < 6) {
        debugPrint(
          '[_tryReadTUnion] READ BALANCE response too short: ${balRes.length}',
        );
        return null;
      }

      final balSw1 = balRes[balRes.length - 2];
      final balSw2 = balRes[balRes.length - 1];
      if (balSw1 != 0x90 || balSw2 != 0x00) {
        debugPrint('[_tryReadTUnion] READ BALANCE SW != 9000');
        return null;
      }

      final balanceCents =
          (balRes[0] << 24) | (balRes[1] << 16) | (balRes[2] << 8) | balRes[3];
      final balance = balanceCents / 100.0;
      debugPrint('[_tryReadTUnion] parsed balance: $balance');

      // 4. READ TRANSACTION HISTORY: SFI 0x18 (read up to 10 records)
      final List<TransitTransaction> transactions = [];
      if (readExtended) {
        debugPrint(
          '[_tryReadTUnion] readExtended is true, querying transaction logs...',
        );
        for (int recNum = 1; recNum <= 10; recNum++) {
          final readRecord = Uint8List.fromList([
            0x00,
            0xB2,
            recNum,
            0xC4,
            0x00,
          ]);
          final recRes = await transceiver.transceive(readRecord);
          debugPrint(
            '[_tryReadTUnion] Record $recNum response length: ${recRes.length}',
          );
          if (recRes.length < 2) {
            debugPrint('[_tryReadTUnion] Record $recNum response too short');
            break;
          }

          final recSw1 = recRes[recRes.length - 2];
          final recSw2 = recRes[recRes.length - 1];
          debugPrint(
            '[_tryReadTUnion] Record $recNum SW: ${recSw1.toRadixString(16).toUpperCase()}${recSw2.toRadixString(16).toUpperCase()}',
          );
          if (recSw1 != 0x90 || recSw2 != 0x00) {
            break;
          }

          final recordData = recRes.sublist(0, recRes.length - 2);
          if (recordData.length < 23) {
            debugPrint(
              '[_tryReadTUnion] Record $recNum payload too short: ${recordData.length}',
            );
            continue;
          }

          if (recordData.every((b) => b == 0 || b == 0xFF)) {
            debugPrint(
              '[_tryReadTUnion] Record $recNum is empty (all zeros/FF)',
            );
            continue;
          }

          final seq = (recordData[0] << 8) | recordData[1];
          if (seq == 0) {
            debugPrint('[_tryReadTUnion] Record $recNum has sequence 0');
            continue;
          }
          final amountCents =
              (recordData[5] << 24) |
              (recordData[6] << 16) |
              (recordData[7] << 8) |
              recordData[8];
          final amount = amountCents / 100.0;
          final typeCode = recordData[9];

          final terminalId = recordData
              .sublist(10, 16)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .toUpperCase();

          // Date (YYYYMMDD) and Time (HHMMSS) in BCD format
          final dateHex = recordData
              .sublist(16, 20)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final timeHex = recordData
              .sublist(20, 23)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();

          final yearStr = dateHex.substring(0, 4);
          final monthStr = dateHex.substring(4, 6);
          final dayStr = dateHex.substring(6, 8);
          final hourStr = timeHex.substring(0, 2);
          final minStr = timeHex.substring(2, 4);
          final secStr = timeHex.substring(4, 6);

          final dateTimeStr =
              "$yearStr-$monthStr-${dayStr}T$hourStr:$minStr:$secStr";
          final txDateTime = DateTime.tryParse(dateTimeStr);

          final typeStr = _getTUnionProcessType(typeCode, amountCents);
          final details = "Terminal: $terminalId";

          debugPrint(
            '[_tryReadTUnion] Record $recNum parsed: Date=$txDateTime, Type=$typeStr, Amount=$amount, Seq=$seq',
          );
          transactions.add(
            TransitTransaction(
              date: txDateTime,
              type: typeStr,
              amount: typeStr == 'Top-up' ? amount : -amount,
              details: details,
              terminalId: terminalId,
              seq: seq,
            ),
          );
        }
      }

      final tunion = TUnion(
        tag.id,
        tag.sak,
        tag.atqa,
        cardNumber: cardNumber,
        balance: balance,
        transactions: transactions,
        snapshotTime: DateTime.now(),
      );

      debugPrint(
        '[_tryReadTUnion] Reading successful. Transactions count: ${transactions.length}',
      );
      return ScannedCard(card: tunion, source: source);
    } catch (e, s) {
      debugPrint('[_tryReadTUnion] Fatal error reading T-Union: $e\n$s');
      return null;
    }
  }

  String _getTUnionProcessType(int typeCode, int amountCents) {
    switch (typeCode) {
      case 0x09:
        return 'Ride';
      case 0x06:
        return 'Shopping';
      case 0x01:
      case 0x02:
        return 'Top-up';
      case 0x05:
        return 'Refund';
      default:
        return 'Other';
    }
  }
}
