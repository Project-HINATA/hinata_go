import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'nfc_card_channel.dart';
import 'nfc_exception.dart';

class PhoneNfcCardChannel implements NfcCardChannel {
  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    try {
      final hexStr = hex.encode(data).toUpperCase();
      final responseHex = await FlutterNfcKit.transceive(
        hexStr,
        timeout: timeout,
      );
      return Uint8List.fromList(hex.decode(responseHex));
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'Phone NFC transceive failed',
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
    try {
      late final bool authenticated;
      if (keyA != null) {
        authenticated = await FlutterNfcKit.authenticateSector(
          block ~/ 4,
          keyA: keyA,
        );
      } else if (keyB != null) {
        authenticated = await FlutterNfcKit.authenticateSector(
          block ~/ 4,
          keyB: keyB,
        );
      } else {
        throw ArgumentError('A Mifare key is required');
      }
      if (!authenticated) {
        throw NfcException(
          type: NfcErrorType.authFailed,
          message: 'Phone Mifare authentication rejected the key',
        );
      }
    } on NfcException {
      rethrow;
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'Phone Mifare authentication was interrupted',
        originalError: e,
      );
    }
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    try {
      final res = await FlutterNfcKit.readBlock(block);
      return res;
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.readError,
        message: 'Phone Mifare read failed',
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
      await FlutterNfcKit.writeBlock(block, data);
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.writeError,
        message: 'Phone Mifare write failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> reconnect() async {
    // Native implementations handle automatic reconnection or do not strict HALT on failed auth.
  }

  @override
  Future<void> close() async {
    await FlutterNfcKit.finish();
  }
}
