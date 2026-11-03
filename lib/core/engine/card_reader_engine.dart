import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:hinata_go/models/card/aic.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/felica_dump.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hinata_go/models/card/nesica.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/suica.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/models/card/transit.dart';

import '../crypto/mifare_key.dart';
import '../validators/access_code_validator.dart';
import '../data/tunion_data.dart';
import 'felica_dump_reader.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

class CardReaderEngine {
  static const _tUnionInfoReadAttempts = 3;
  static const _tUnionInfoRetryDelay = Duration(milliseconds: 50);

  final NfcCardChannel transceiver;

  /// How many FeliCa blocks one read asks for, as many as [transceiver]
  /// passes back.
  final int felicaBlocksPerRead;

  CardReaderEngine(this.transceiver, {this.felicaBlocksPerRead = 2});

  static const int _aimeAccessCodeStart = 6;
  static const int _aimeAccessCodeEnd = 16;

  /// Resolves a FeliCa tag to an Amusement IC, a Suica or a plain FeliCa
  /// card, from its blocks. Without [readExtended] only the first batch is
  /// read, the blocks that tell the kind of card apart (see
  /// [FelicaDumpReader.readFirst]); with it, every block that reads without
  /// encryption, over what [existingCard] already read.
  ///
  /// [onProgress] gets the card as it stands while the read goes on: once
  /// its system codes are listed, and after each record of a Suica's
  /// history.
  Future<ScannedCard?> handleFelica({
    required Felica tag,
    String source = 'NFC',
    bool readExtended = true,
    ScannedCard? existingCard,
    void Function(ScannedCard card)? onProgress,
  }) async {
    final reader = FelicaDumpReader(
      transceiver,
      blocksPerRead: felicaBlocksPerRead,
    );

    if (!readExtended) {
      final FelicaDump? first;
      try {
        first = await reader.readFirst(tag);
      } catch (e) {
        log('CardReaderEngine Felica error: $e');
        throw NfcException(
          type: NfcErrorType.readError,
          message: 'Failed to read FeliCa data',
          originalError: e,
        );
      }
      if (first == null) return ScannedCard(card: tag, source: source);
      return _scannedFelica(tag, first, source: source);
    }

    // What the first read found stays if the card leaves before it is read
    // again.
    final shown = existingCard?.card;
    final earlier = shown is Felica && shown.isSameCard(tag)
        ? shown.dump
        : null;
    ScannedCard scanned(FelicaDump dump) => _scannedFelica(
      tag,
      earlier?.overlaidWith(dump) ?? dump,
      source: source,
    );

    // The system codes show as soon as they are listed, then a Suica's
    // history record by record, before the rest of the services are read.
    final dump = await reader.read(
      tag,
      first: tag.systemCode.contains(0x0003)
          ? const [Suica.historyService]
          : const [],
      onProgress: onProgress == null
          ? null
          : (dump) => onProgress(scanned(dump)),
    );
    return scanned(dump);
  }

  /// [tag] as the kind of card [dump] shows it is.
  ScannedCard _scannedFelica(
    Felica tag,
    FelicaDump dump, {
    required String source,
  }) {
    // Polling names one system; the dump lists them all once it can.
    final systemCode = dump.systemCodes.length > tag.systemCode.length
        ? Uint16List.fromList(dump.systemCodes)
        : tag.systemCode;
    final spad0 = dump.block(Aic.service, Aic.spad0Block);
    final ICCard card;
    if (_mayAic(tag.id, tag.pmm, tag.systemCode) &&
        spad0 != null &&
        Aic.holdsAccessCode(spad0)) {
      final manufacturer = Aic(
        tag.id,
        tag.pmm,
        systemCode,
        dump: dump,
      ).manufacturer;
      card = Aic(
        tag.id,
        tag.pmm,
        systemCode,
        dump: dump,
        tags: [
          CardTag.amusementIc,
          if (manufacturer != 'Unknown') CardTag.fromRawString(manufacturer),
          CardTag.felica,
        ],
      );
    } else if (systemCode.contains(0x0003) &&
        dump.services[Suica.historyService]?.isNotEmpty == true) {
      card = Suica.fromDump(
        tag.id,
        tag.pmm,
        systemCode,
        dump,
        snapshotTime: DateTime.now(),
        tags: _suicaTags,
      );
    } else {
      card = Felica(tag.id, tag.pmm, systemCode, tags: tag.tags, dump: dump);
    }
    return ScannedCard(
      card: card,
      source: source,
      isExtendedInfoFullyLoaded: dump.complete,
    );
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
      tags: const [CardTag.banapass, CardTag.mifareClassic],
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
    final aime = tag.toAime(
      accessCodeBytes,
      tags: const [CardTag.aime, CardTag.mifareClassic],
    );
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
      tags: const [CardTag.banapass, CardTag.mifareClassic],
    );

    return AccessCodeValidator.isValidDecodedBanapassAccessCode(
          banapass.accessCodeString,
        )
        ? banapass
        : null;
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
    void Function(ScannedCard card)? onProgress,
  }) async {
    if (rawTag is Felica) {
      try {
        final card = await handleFelica(
          tag: rawTag,
          source: source,
          readExtended: readExtended,
          existingCard: existingCard,
          onProgress: onProgress,
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

      final nesica = await _tryReadNesica(rawTag, source: source);
      if (nesica != null) return CardReadResult.recognized(nesica);

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

  /// Reads an old NESiCA card, which is a MIFARE Ultralight.
  ///
  /// The card does not authenticate, so it is read with raw READ commands
  /// ([0x30, page]). Returns null for MIFARE Classic, ISO-DEP and NDEF-formatted
  /// tags, and for any tag that does not carry the NESiCA marker, so the caller
  /// can fall back to [_unsupported].
  Future<ScannedCard?> _tryReadNesica(
    Iso14443 tag, {
    required String source,
  }) async {
    // Skip MIFARE Classic (SAK bit 3) and ISO-DEP (SAK bit 5) cards.
    if ((tag.sak & 0x08) != 0 || (tag.sak & 0x20) != 0 || tag.id.length < 7) {
      return null;
    }

    var serial = '';
    try {
      final pages = <int>[];
      for (final pageStart in const [0x00, 0x04, 0x08]) {
        final response = await transceiver.transceive(
          Uint8List.fromList([0x30, pageStart]),
        );
        if (response.length < 16) break;
        pages.addAll(response.take(16));
      }
      if (pages.length < 36) return null;
      // Reject NFC Forum Type 2 (NDEF) tags by their capability container.
      if (pages[12] == 0xE1) return null;
      // NESiCA cards start page 4 with 'T'.
      if (pages[16] != 0x54) return null;
      serial = _decodeAscii(pages.sublist(20, 36));
    } catch (e) {
      debugPrint('[CardReaderEngine] NESiCA read failed: $e');
      return null;
    }

    return ScannedCard(
      card: Nesica(
        tag.id,
        tag.sak,
        tag.atqa,
        serial: serial,
        tags: const [CardTag.nesica],
      ),
      source: source,
    );
  }

  /// Decodes a run of printable ASCII bytes, stopping at the first
  /// non-printable byte.
  String _decodeAscii(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x20 || byte > 0x7E) break;
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }

  static const _suicaTags = [
    CardTag.suica,
    CardTag.japanTransit,
    CardTag.felica,
  ];

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

      // Extract Card Type (Byte 9)
      int rawCardType = infoRes.length > 9 ? infoRes[9] : 0;
      String cardTypeStr = rawCardType
          .toRadixString(16)
          .padLeft(2, '0')
          .toUpperCase();

      // Extract Dates (Bytes 20-23 start, 24-27 expiry) YYYYMMDD in Hex/BCD
      String? issueDate;
      String? expiryDate;
      if (infoRes.length >= 28) {
        final startBytes = infoRes.sublist(20, 24);
        final endBytes = infoRes.sublist(24, 28);

        String parseDateBytes(Uint8List b) {
          final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
          if (s.length == 8) {
            return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
          }
          return s;
        }

        issueDate = parseDateBytes(startBytes);
        expiryDate = parseDateBytes(endBytes);
      }

      // Interconnect check (usually T-Union implies interconnected, we can set true)
      bool isInterchangeEnabled = true;

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
      // China T-Union cards store rich transit trip logs in SFI 0x1E (48-byte MOT Combined Log File, up to 30~60 records).
      // Older / regional cards (e.g. Shanghai CU) store 23-byte PBOC records in SFI 0x18 (up to 10~30 records).
      final List<Uint8List?> blocksData = [];
      bool isFile1E = false;
      int recordSfi = 0x1E;
      int expectedLen = 0x30;

      if (existingCard != null && existingCard.card is TUnion) {
        final existingTUnion = existingCard.card as TUnion;
        for (final blk in existingTUnion.rawBlocks) {
          if (blk != null) blocksData.add(blk);
        }
      }

      bool fullyLoaded = readExtended;
      if (readExtended) {
        if (blocksData.isEmpty) {
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
              blocksData.add(rec1Data);
            }
          }

          if (!isFile1E) {
            // Fall back to SFI 0x18
            recordSfi = 0x18;
            expectedLen = 0x17;
            final rec18Data = await _readTUnionRecord(
              transceiver,
              recNum: 1,
              sfi: 0x18,
              expectedLen: 0x17,
            );
            if (rec18Data != null && rec18Data.length >= 23) {
              blocksData.add(rec18Data);
            }
          }
        } else {
          // Detect whether existing records are 0x1E or 0x18 based on length
          if (blocksData.first != null && blocksData.first!.length >= 48) {
            isFile1E = true;
            recordSfi = 0x1E;
            expectedLen = 0x30;
          } else {
            isFile1E = false;
            recordSfi = 0x18;
            expectedLen = 0x17;
          }
        }

        final maxRecords = isFile1E ? 60 : 30;
        final startRec = blocksData.length + 1;
        for (int recNum = startRec; recNum <= maxRecords; recNum++) {
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
            break;
          }

          if (isFile1E) {
            final dateHex = recordData
                .sublist(25, 29)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            final year = int.tryParse(dateHex.substring(0, 4)) ?? 0;
            if (year < 2000 || year > 2099) {
              break;
            }
          }

          blocksData.add(recordData);
        }
      }

      final List<TransitTransaction> transactions = [];
      final cardCityCode = cardNumber.length >= 4
          ? cardNumber.substring(0, 4)
          : '';

      for (int i = 0; i < blocksData.length; i++) {
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
              ? '0001'
              : (industryByte == 0x02
                    ? '0002'
                    : (industryByte == 0x03 ? '0003' : ''));
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
            stationCode:
                stationCode.replaceAll(RegExp(r'(00)+$'), '').isNotEmpty
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
              txDateTime = DateTime.tryParse(
                '$yStr-$mStr-${dStr}T$hStr:$miStr:$sStr',
              );
            }
          }

          final typeStr = _getTUnionProcessType(typeCode, amountCents);
          final termCity =
              terminalId.length >= 4 &&
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

      final issuer = lookupTUnionIssuer(cardNumber);
      final tags = [
        if (issuer != null && issuer.isNotEmpty) CardTag.issuer(issuer),
        CardTag.tUnion,
        CardTag.isoDep,
      ];

      final tunion = TUnion(
        tag.id,
        tag.sak,
        tag.atqa,
        cardNumber: cardNumber,
        balance: balance,
        transactions: transactions,
        snapshotTime: DateTime.now(),
        cardType: cardTypeStr,
        issueDate: issueDate,
        expiryDate: expiryDate,
        isInterchangeEnabled: isInterchangeEnabled,
        tags: tags,
        rawBlocks: blocksData,
        isHistoryComplete: fullyLoaded,
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
      final fallbackLen = expectedLen == 0 ? (sfi == 0x1E ? 0x30 : 0x17) : 0x00;
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
