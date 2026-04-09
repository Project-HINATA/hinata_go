import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'nfc_transceiver.dart';
import 'nfc_exception.dart';

class NativeNfcTransceiver implements NfcTransceiver {
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
        message: 'Native NFC transceive failed',
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
      if (keyA != null) {
        await FlutterNfcKit.authenticateSector(block ~/ 4, keyA: keyA);
      } else if (keyB != null) {
        await FlutterNfcKit.authenticateSector(block ~/ 4, keyB: keyB);
      }
    } catch (e) {
      throw NfcException(
        type: NfcErrorType.authFailed,
        message: 'Native Mifare authentication failed',
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
        message: 'Native Mifare read failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> close() async {
    // Optional: FlutterNfcKit.finish() can be called here if needed,
    // but usually handled by the provider/service.
  }
}
