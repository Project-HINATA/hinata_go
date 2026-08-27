import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/models/card/transit.dart';

import '../../constants/mifare_key.dart';
import '../../utils/access_code_validator.dart';
import '../../utils/spad0.dart';
import '../../utils/tunion_data.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

class CardReaderEngine {
  static const _tUnionInfoReadAttempts = 3;
  static const _tUnionInfoRetryDelay = Duration(milliseconds: 50);

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
    ScannedCard? existingCard,
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
          existingCard: existingCard,
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

  Future<CardReadResult> readMifareWithBanaKey({
    required Iso14443 tag,
    String source = 'NFC',
  }) async {
    await transceiver.authenticateMifare(
      uid: tag.id,
      block: 1, // Sector 0
      keyA: Uint8List.fromList(banaKey),
    );

    final block1 = await transceiver.readMifareBlock(1);
    final block2 = await transceiver.readMifareBlock(2);
    if (block1.length != 16 || block2.length != 16) {
      return const CardReadResult.incomplete();
    }

    final banapass = tag.toBanapass(
      Uint8List.fromList(block1),
      Uint8List.fromList(block2),
    );
    if (AccessCodeValidator.isValidDecodedBanapassAccessCode(
      banapass.accessCodeString,
    )) {
      return CardReadResult.recognized(
        ScannedCard(card: banapass, source: source),
      );
    }

    return _unsupported(tag, source);
  }

  Future<CardReadResult> readMifareWithAimeKey({
    required Iso14443 tag,
    String source = 'NFC',
  }) async {
    await transceiver.authenticateMifare(
      uid: tag.id,
      block: 2, // Sector 0
      keyB: Uint8List.fromList(aimeKey),
    );

    final block2 = await transceiver.readMifareBlock(2);
    if (block2.length != 16) {
      return const CardReadResult.incomplete();
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
          ? CardReadResult.recognized(
              ScannedCard(card: banapass, source: source),
            )
          : _unsupported(tag, source);
    }

    if (!AccessCodeValidator.isValidAimeAccessCode(aimeAccessCode)) {
      return _unsupported(tag, source);
    }

    return CardReadResult.recognized(ScannedCard(card: aime, source: source));
  }

  Future<Banapass?> _readBanapassFromAimeAuthenticatedSector({
    required Iso14443 tag,
    required Uint8List block2,
  }) async {
    final block1 = await transceiver.readMifareBlock(1);
    if (block1.length != 16) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'Incomplete Mifare block 1',
      );
    }
    final banapass = tag.toBanapass(
      Uint8List.fromList(block1),
      Uint8List.fromList(block2),
    );

    return AccessCodeValidator.isValidDecodedBanapassAccessCode(
          banapass.accessCodeString,
        )
        ? banapass
        : null;
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
  Future<CardReadResult> processTag(
    dynamic rawTag, {
    String source = 'NFC',
    bool readExtended = true,
    ScannedCard? existingCard,
  }) async {
    if (rawTag is Felica) {
      try {
        final card = await handleFelica(
          tag: rawTag,
          source: source,
          readExtended: readExtended,
          existingCard: existingCard,
        );
        return card == null
            ? const CardReadResult.incomplete()
            : CardReadResult.recognized(card);
      } catch (_) {
        return const CardReadResult.incomplete();
      }
    }

    if (rawTag is Iso14443) {
      // Path 1: Mifare Classic (SAK bit 3) → authenticate + read sectors
      if (rawTag.isMifareClassicCandidate) {
        try {
          return await readMifareWithAimeKey(tag: rawTag, source: source);
        } on NfcException catch (error) {
          if (error.type == NfcErrorType.readError) {
            try {
              await transceiver.reconnect();
              return await readMifareWithAimeKey(tag: rawTag, source: source);
            } on NfcException catch (retryError) {
              debugPrint(
                '[CardReaderEngine] MIFARE Key B fast retry incomplete: '
                '$retryError; cause: ${retryError.originalError}',
              );
              return const CardReadResult.incomplete();
            } catch (retryError) {
              debugPrint(
                '[CardReaderEngine] MIFARE Key B fast retry incomplete: '
                '$retryError',
              );
              return const CardReadResult.incomplete();
            }
          }
          if (error.type != NfcErrorType.authFailed) {
            debugPrint(
              '[CardReaderEngine] MIFARE Key B path incomplete: '
              '$error; cause: ${error.originalError}',
            );
            return const CardReadResult.incomplete();
          }
        }

        try {
          await transceiver.reconnect();
          return await readMifareWithBanaKey(tag: rawTag, source: source);
        } on NfcException catch (error) {
          if (error.type != NfcErrorType.authFailed) {
            debugPrint(
              '[CardReaderEngine] MIFARE Key A path incomplete: '
              '$error; cause: ${error.originalError}',
            );
          }
          return error.type == NfcErrorType.authFailed
              ? _unsupported(rawTag, source)
              : const CardReadResult.incomplete();
        } catch (error) {
          debugPrint(
            '[CardReaderEngine] MIFARE reconnect/read incomplete: $error',
          );
          return const CardReadResult.incomplete();
        }
      }

      // Path 2: CPU card / ISO14443-4 (SAK bit 5) → try T-Union
      if ((rawTag.sak & 0x20) != 0) {
        final tunion = await _tryReadTUnion(
          rawTag,
          source: source,
          readExtended: readExtended,
          existingCard: existingCard,
        );
        if (tunion.status == CardReadStatus.recognized) {
          return tunion;
        }

        // Keep the basic card visible if a later extended read loses the
        // ISO-DEP session instead of returning it as a different card type.
        if (readExtended && existingCard?.card is TUnion) {
          debugPrint(
            '[CardReaderEngine] T-Union extended read failed; keeping basic card',
          );
          return CardReadResult.recognized(existingCard!);
        }
        return tunion;
      }

      return _unsupported(rawTag, source);
    }

    // Pass through Iso15693 or any other generic parsed tags
    if (rawTag is Iso15693) {
      return CardReadResult.recognized(
        ScannedCard(card: rawTag, source: source),
      );
    }

    return const CardReadResult.noTarget();
  }

  CardReadResult _unsupported(Iso14443 tag, String source) {
    return CardReadResult.confirmedUnsupported(
      ScannedCard(card: tag, source: source, isUsable: false),
    );
  }

  Future<ScannedCard?> _tryReadSuica(
    Felica tag, {
    required String source,
    bool readExtended = true,
    ScannedCard? existingCard,
  }) async {
    try {
      final List<Uint8List?> blocksData = List.filled(20, null);
      final List<double?> blockBalances = List.filled(20, null);
      double balance = 0.0;

      if (existingCard != null && existingCard.card is Suica) {
        final existingSuica = existingCard.card as Suica;
        for (int i = 0; i < 20; i++) {
          if (i < existingSuica.rawBlocks.length) {
            blocksData[i] = existingSuica.rawBlocks[i];
          }
          if (i < existingSuica.rawBalances.length) {
            blockBalances[i] = existingSuica.rawBalances[i];
          }
        }
        balance = existingSuica.balance;
      }

      // Suica history service code is 0x090F
      const int suicaServiceCode = 0x090F;

      final int blocksToRead = readExtended ? 20 : 1;
      bool fullyLoaded = readExtended;
      for (int blockIndex = 0; blockIndex < blocksToRead; blockIndex++) {
        if (blocksData[blockIndex] != null) {
          continue; // Already read!
        }

        // Read block using FeliCa Read Without Encryption
        final response = await felicaReadWithoutEncryption(tag.id, [
          blockIndex,
        ], serviceCode: suicaServiceCode);

        debugPrint(
          '[_tryReadSuica] Block $blockIndex response len=${response.length}: ${response.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}',
        );

        // Response should contain length, response code, IDm, status flags, block count, block data
        // status flags are at index 10 and 11, block data starts at index 13
        if (response.length < 29) {
          fullyLoaded = false;
          break; // Response too short or read finished
        }

        final status1 = response[10];
        final status2 = response[11];
        if (status1 != 0 || status2 != 0) {
          fullyLoaded = false;
          break; // Non-zero status flags indicate end of records or error
        }

        final blockData = response.sublist(13, 29);
        final blockBalance = blockData[10] | (blockData[11] << 8);

        if (blockIndex == 0) {
          balance = blockBalance.toDouble();
        }

        blocksData[blockIndex] = blockData;
        blockBalances[blockIndex] = blockBalance.toDouble();
      }

      final List<TransitTransaction> transactions = [];
      for (int i = 0; i < 20; i++) {
        final blockData = blocksData[i];
        if (blockData == null) continue;

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

        double amt = 0.0;
        if (i + 1 < 20 && blockBalances[i + 1] != null) {
          amt = blockBalances[i]! - blockBalances[i + 1]!;
        }

        final tx = Suica.parseTransaction(blockData, amt);
        transactions.add(tx);
      }

      final suica = Suica(
        tag.id,
        tag.pmm,
        tag.systemCode,
        balance: balance,
        transactions: transactions,
        snapshotTime: DateTime.now(),
        rawBlocks: blocksData,
        rawBalances: blockBalances,
      );

      return ScannedCard(
        card: suica,
        source: source,
        isExtendedInfoFullyLoaded: fullyLoaded,
      );
    } catch (e) {
      log('CardReaderEngine Suica read error: $e');
      return null;
    }
  }

  /// Try to read ISO14443-4 T-Union card info, balance, and transaction history
  Future<CardReadResult> _tryReadTUnion(
    Iso14443 tag, {
    required String source,
    bool readExtended = true,
    ScannedCard? existingCard,
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
        return const CardReadResult.incomplete();
      }

      final sw1 = selectRes[selectRes.length - 2];
      final sw2 = selectRes[selectRes.length - 1];
      debugPrint(
        '[_tryReadTUnion] SELECT AID SW: ${_formatStatusWord(sw1, sw2)}',
      );
      if (sw1 != 0x90 || sw2 != 0x00) {
        debugPrint(
          '[_tryReadTUnion] Not a China T-Union card (SELECT SW != 9000)',
        );
        return _unsupported(tag, source);
      }

      // 2. READ CARD BASIC INFO: SFI 0x15
      final readInfo = Uint8List.fromList([0x00, 0xB0, 0x95, 0x00, 0x1E]);
      var infoRes = Uint8List(0);
      for (var attempt = 1; attempt <= _tUnionInfoReadAttempts; attempt++) {
        try {
          infoRes = await transceiver.transceive(readInfo);
        } catch (e) {
          debugPrint('[_tryReadTUnion] READ INFO attempt $attempt failed: $e');
          infoRes = Uint8List(0);
        }

        debugPrint(
          '[_tryReadTUnion] READ INFO attempt $attempt response length: ${infoRes.length}',
        );
        if (infoRes.length >= 32 || attempt == _tUnionInfoReadAttempts) {
          break;
        }
        await Future<void>.delayed(_tUnionInfoRetryDelay);
      }
      debugPrint(
        '[_tryReadTUnion] READ INFO response length: ${infoRes.length}',
      );
      if (infoRes.length < 32) {
        debugPrint(
          '[_tryReadTUnion] READ INFO response too short: ${infoRes.length}',
        );
        return const CardReadResult.incomplete();
      }

      final infoSw1 = infoRes[infoRes.length - 2];
      final infoSw2 = infoRes[infoRes.length - 1];
      if (infoSw1 != 0x90 || infoSw2 != 0x00) {
        debugPrint('[_tryReadTUnion] READ INFO SW != 9000');
        return const CardReadResult.incomplete();
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
        return const CardReadResult.incomplete();
      }

      final balSw1 = balRes[balRes.length - 2];
      final balSw2 = balRes[balRes.length - 1];
      if (balSw1 != 0x90 || balSw2 != 0x00) {
        debugPrint('[_tryReadTUnion] READ BALANCE SW != 9000');
        return const CardReadResult.incomplete();
      }

      final balanceCents =
          (balRes[0] << 24) | (balRes[1] << 16) | (balRes[2] << 8) | balRes[3];
      final balance = balanceCents / 100.0;
      debugPrint('[_tryReadTUnion] parsed balance: $balance');

      // 4. READ TRANSACTION HISTORY
      // China T-Union cards store rich transit trip logs in SFI 0x1E (48-byte MOT Combined Log File, APDU: 00 B2 <rec> F4 00).
      // Older / regional cards (e.g. Shanghai CU) store 23-byte PBOC records in SFI 0x18 (APDU: 00 B2 <rec> C4 00).
      final List<Uint8List?> blocksData = List.filled(10, null);
      bool isFile1E = false;
      int recordSfi = 0x1E;
      int expectedLen = 0x30;

      if (existingCard != null && existingCard.card is TUnion) {
        final existingTUnion = existingCard.card as TUnion;
        for (int i = 0; i < 10; i++) {
          if (i < existingTUnion.rawBlocks.length) {
            blocksData[i] = existingTUnion.rawBlocks[i];
          }
        }
      }

      bool fullyLoaded = readExtended;
      if (readExtended) {
        // Probe SFI 0x1E Record 1
        final rec1Data = await _readTUnionRecord(
          transceiver,
          recNum: 1,
          sfi: 0x1E,
          expectedLen: 0x30,
        );

        if (rec1Data != null && rec1Data.length >= 48) {
          final dateHex = rec1Data
              .sublist(25, 29)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final year = int.tryParse(dateHex.substring(0, 4)) ?? 0;
          final month = int.tryParse(dateHex.substring(4, 6)) ?? 0;
          final day = int.tryParse(dateHex.substring(6, 8)) ?? 0;
          if (year >= 2000 &&
              year <= 2099 &&
              month >= 1 &&
              month <= 12 &&
              day >= 1 &&
              day <= 31) {
            isFile1E = true;
            blocksData[0] = rec1Data;
          }
        }

        if (!isFile1E) {
          // Fall back to SFI 0x18
          recordSfi = 0x18;
          expectedLen = 0x17;
          if (blocksData[0] == null) {
            final rec18Data = await _readTUnionRecord(
              transceiver,
              recNum: 1,
              sfi: 0x18,
              expectedLen: 0x17,
            );
            if (rec18Data != null && rec18Data.length >= 23) {
              blocksData[0] = rec18Data;
            }
          }
        }

        final startRec = (blocksData[0] != null) ? 2 : 1;
        for (int recNum = startRec; recNum <= 10; recNum++) {
          if (blocksData[recNum - 1] != null) continue;

          final recordData = await _readTUnionRecord(
            transceiver,
            recNum: recNum,
            sfi: recordSfi,
            expectedLen: expectedLen,
          );

          if (recordData == null) break;

          final minLen = isFile1E ? 48 : 23;
          if (recordData.length < minLen ||
              recordData.every((b) => b == 0 || b == 0xFF)) {
            continue;
          }

          blocksData[recNum - 1] = recordData;
        }
      }

      final List<TransitTransaction> transactions = [];
      final cardCityCode =
          cardNumber.length >= 4 ? cardNumber.substring(0, 4) : '';

      for (int i = 0; i < 10; i++) {
        final recordData = blocksData[i];
        if (recordData == null) continue;

        if (isFile1E && recordData.length >= 48) {
          // Parse JT/T 978 SFI 0x1E 48-Byte Composite Record
          final typeCode = recordData[0];
          final terminalId = recordData
              .sublist(1, 9)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .toUpperCase();
          final industryByte = recordData[9];
          final industryCode = industryByte == 0x01
              ? '0002'
              : (industryByte == 0x02 ? '0001' : '');
          final stationCode = recordData
              .sublist(10, 17)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .toUpperCase();
          final amountCents =
              (recordData[17] << 24) |
              (recordData[18] << 16) |
              (recordData[19] << 8) |
              recordData[20];
          final amount = amountCents / 100.0;

          final dateHex = recordData
              .sublist(25, 29)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final timeHex = recordData
              .sublist(29, 32)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();

          final cityCode = recordData
              .sublist(32, 34)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .toUpperCase();

          DateTime? txDateTime;
          if (dateHex.length == 8 && timeHex.length == 6) {
            final y = dateHex.substring(0, 4);
            final m = dateHex.substring(4, 6);
            final d = dateHex.substring(6, 8);
            final hr = timeHex.substring(0, 2);
            final min = timeHex.substring(2, 4);
            final sec = timeHex.substring(4, 6);
            txDateTime = DateTime.tryParse('$y-$m-${d}T$hr:$min:$sec');
          }

          final typeStr = _getTUnionProcessType(typeCode, amountCents);
          final details = TUnion.formatTransactionDetails(
            cityCode: cityCode != '0000' ? cityCode : cardCityCode,
            stationCode: stationCode.replaceAll(RegExp(r'(00)+$'), '').isNotEmpty
                ? stationCode
                : null,
            terminalId: terminalId != '0000000000000000' ? terminalId : null,
            industryCode: industryCode,
            typeCode: typeCode,
            amount: amount,
          );

          transactions.add(
            TransitTransaction(
              date: txDateTime,
              type: typeStr,
              amount: typeStr == 'Top-up' ? amount : -amount,
              details: details.isNotEmpty ? details : 'Terminal: $terminalId',
              terminalId: terminalId,
              seq: i + 1,
            ),
          );
        } else if (recordData.length >= 23) {
          // Parse Standard PBOC SFI 0x18 Record (23 bytes)
          final seq = (recordData[0] << 8) | recordData[1];
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

          final dateHex = recordData
              .sublist(16, 20)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final timeHex = recordData
              .sublist(20, 23)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();

          DateTime? txDateTime;
          if (dateHex.length == 8 && timeHex.length == 6) {
            final year = int.tryParse(dateHex.substring(0, 4)) ?? 0;
            final month = int.tryParse(dateHex.substring(4, 6)) ?? 0;
            final day = int.tryParse(dateHex.substring(6, 8)) ?? 0;
            final hr = int.tryParse(timeHex.substring(0, 2)) ?? 0;
            final min = int.tryParse(timeHex.substring(2, 4)) ?? 0;
            final sec = int.tryParse(timeHex.substring(4, 6)) ?? 0;

            if (year >= 2000 &&
                year <= 2099 &&
                month >= 1 &&
                month <= 12 &&
                day >= 1 &&
                day <= 31 &&
                hr < 24 &&
                min < 60 &&
                sec < 60) {
              final yStr = year.toString().padLeft(4, '0');
              final mStr = month.toString().padLeft(2, '0');
              final dStr = day.toString().padLeft(2, '0');
              final hStr = hr.toString().padLeft(2, '0');
              final miStr = min.toString().padLeft(2, '0');
              final sStr = sec.toString().padLeft(2, '0');
              txDateTime =
                  DateTime.tryParse('$yStr-$mStr-${dStr}T$hStr:$miStr:$sStr');
            }
          }

          final typeStr = _getTUnionProcessType(typeCode, amountCents);
          final termCity = terminalId.length >= 4 &&
                  tunionCityMap.containsKey(terminalId.substring(0, 4))
              ? terminalId.substring(0, 4)
              : cardCityCode;

          final details = TUnion.formatTransactionDetails(
            cityCode: termCity,
            terminalId: terminalId,
            amount: amount,
          );

          transactions.add(
            TransitTransaction(
              date: txDateTime,
              type: typeStr,
              amount: typeStr == 'Top-up' ? amount : -amount,
              details: details.isNotEmpty ? details : 'Terminal: $terminalId',
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
        rawBlocks: blocksData,
      );

      debugPrint(
        '[_tryReadTUnion] Reading successful. Transactions count: ${transactions.length}',
      );
      return CardReadResult.recognized(
        ScannedCard(
          card: tunion,
          source: source,
          isExtendedInfoFullyLoaded: fullyLoaded,
        ),
      );
    } catch (e, s) {
      debugPrint('[_tryReadTUnion] Fatal error reading T-Union: $e\n$s');
      return const CardReadResult.incomplete();
    }
  }

  Future<Uint8List?> _readTUnionRecord(
    NfcCardChannel transceiver, {
    required int recNum,
    required int sfi,
    int expectedLen = 0,
  }) async {
    final p2 = (sfi << 3) | 0x04;
    var cmd = Uint8List.fromList([0x00, 0xB2, recNum, p2, expectedLen]);
    var res = await transceiver.transceive(cmd);

    if (res.length >= 2 &&
        res[res.length - 2] == 0x90 &&
        res[res.length - 1] == 0x00) {
      return res.sublist(0, res.length - 2);
    }

    // If card responds with 6C <La> (Wrong Le, re-issue with Le = La)
    if (res.length == 2 && res[0] == 0x6C) {
      final la = res[1];
      cmd = Uint8List.fromList([0x00, 0xB2, recNum, p2, la]);
      res = await transceiver.transceive(cmd);
      if (res.length >= 2 &&
          res[res.length - 2] == 0x90 &&
          res[res.length - 1] == 0x00) {
        return res.sublist(0, res.length - 2);
      }
    }

    // If card responds with 67 00 (Wrong length Le)
    if (res.length == 2 && res[0] == 0x67) {
      final fallbackLen =
          expectedLen == 0 ? (sfi == 0x1E ? 0x30 : 0x17) : 0x00;
      cmd = Uint8List.fromList([0x00, 0xB2, recNum, p2, fallbackLen]);
      res = await transceiver.transceive(cmd);
      if (res.length == 2 && res[0] == 0x6C) {
        final la = res[1];
        cmd = Uint8List.fromList([0x00, 0xB2, recNum, p2, la]);
        res = await transceiver.transceive(cmd);
      }
      if (res.length >= 2 &&
          res[res.length - 2] == 0x90 &&
          res[res.length - 1] == 0x00) {
        return res.sublist(0, res.length - 2);
      }
    }

    return null;
  }

  String _getTUnionProcessType(int typeCode, int amountCents) {
    switch (typeCode) {
      case 0x03:
      case 0x04:
      case 0x09:
      case 0x02:
        return 'Ride';
      case 0x06:
        return 'Ride';
      case 0x01:
        return 'Top-up';
      case 0x05:
        return 'Refund';
      default:
        return 'Ride';
    }
  }

  String _formatStatusWord(int sw1, int sw2) {
    return '${sw1.toRadixString(16).padLeft(2, '0')}'
            '${sw2.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}
