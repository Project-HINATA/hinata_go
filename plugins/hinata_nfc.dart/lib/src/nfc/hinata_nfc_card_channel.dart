import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import '../protocol/pn532.dart';
import 'nfc_card_channel.dart';
import 'nfc_exception.dart';

class HinataNfcCardChannel implements NfcCardChannel {
  final Pn532Api pn532;
  final int tg;
  final Uint8List? expectedUid;

  HinataNfcCardChannel(this.pn532, {this.tg = 1, Uint8List? expectedUid})
    : expectedUid = expectedUid == null
          ? null
          : Uint8List.fromList(expectedUid);

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    try {
      // For FeliCa on PN532, we use inDataExchange.
      // Payload[0] is assumed to be the length byte as per FeliCa protocol.
      // We send the length as the 'cmd' byte for inDataExchange and the rest as data.
      final res = await pn532.inDataExchange(
        tg,
        data[0], // Length byte
        data.sublist(1).toList(),
      );
      log(data.toString());

      if (res.isEmpty) {
        throw NfcException(
          type: NfcErrorType.readError,
          message: 'Empty response from PN532',
        );
      }

      log(res.toString());

      // PN532 returns the response including status byte at res[0] (0x00 for success)
      return Uint8List.fromList(res.sublist(1));
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'HINATA PN532 transceive failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) async {
    final keyType = (keyA != null)
        ? MifareCommand.authA.toInt()
        : MifareCommand.authB.toInt();

    final key = keyA ?? keyB!;
    late final Pn532Error result;
    try {
      result = await pn532.mifareClassicAuth(
        tg,
        uid.toList(),
        block,
        keyType,
        key.toList(),
      );
    } on TimeoutException catch (e) {
      throw NfcException(
        type: NfcErrorType.timeout,
        message: 'HINATA Mifare authentication timed out',
        originalError: e,
      );
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'HINATA Mifare authentication transport failed $keyType',
        originalError: e,
      );
    }

    if (result != Pn532Error.none) {
      throw NfcException(
        type: NfcErrorType.authFailed,
        message: 'PN532 Mifare Auth failed: $result',
      );
    }
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    try {
      final res = await pn532.mifareClassicReadBlock(tg, block);
      if (res == null) {
        throw NfcException(
          type: NfcErrorType.readError,
          message: 'Failed to read Mifare block $block',
        );
      }
      return Uint8List.fromList(res);
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'HINATA Mifare read failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> writeMifareBlock(int block, Uint8List data) async {
    if (data.length != 16) {
      throw ArgumentError.value(data.length, 'data.length', 'Must be 16');
    }
    try {
      final result = Pn532Error.fromValue(
        await pn532.mifareClassicWriteBlock(tg, block, data),
      );
      if (result != Pn532Error.none) {
        throw NfcException(
          type: NfcErrorType.writeError,
          message: 'PN532 Mifare write failed: $result',
        );
      }
    } on NfcException {
      rethrow;
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.writeError,
        message: 'HINATA Mifare write transport failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> reconnect() async {
    // Re-run Type A activation at the current RF power. This both restores a
    // halted MIFARE card and confirms that it is still present before retrying.
    final targets = await pn532.inListPassiveTarget(0, 1, const []);
    if (targets.isEmpty) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'MIFARE target disappeared while reconnecting',
      );
    }
    if (expectedUid case final uid?) {
      final actual = targets.first.id;
      var matches = actual.length == uid.length;
      for (var i = 0; matches && i < uid.length; i++) {
        matches = actual[i] == uid[i];
      }
      if (!matches) {
        throw NfcException(
          type: NfcErrorType.readError,
          message: 'A different MIFARE target appeared while reconnecting',
        );
      }
    }
  }

  @override
  Future<void> close() async {
    await pn532.inRelease(tg);
  }
}
