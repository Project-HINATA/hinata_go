import 'dart:developer';
import 'dart:typed_data';

import '../card/card_io_exception.dart';
import '../card/card_transceiver.dart';
import '../protocols/pn532.dart';

class HinataCardTransceiver implements CardTransceiver {
  final Pn532Api pn532;
  final int tg;

  HinataCardTransceiver(this.pn532, {this.tg = 1});

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
        throw CardIoException(
          type: CardIoErrorType.readError,
          message: 'Empty response from PN532',
        );
      }

      log(res.toString());

      // PN532 returns the response including status byte at res[0] (0x00 for success)
      return Uint8List.fromList(res.sublist(1));
    } catch (e) {
      throw CardIoException(
        type: CardIoErrorType.readError,
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

    try {
      final key = keyA ?? keyB!;

      final result = await pn532.mifareClassicAuth(
        tg,
        uid.toList(),
        block,
        keyType,
        key.toList(),
      );

      if (result != Pn532Error.none) {
        throw CardIoException(
          type: CardIoErrorType.authFailed,
          message: 'PN532 Mifare Auth failed: $result',
        );
      }
    } catch (e) {
      throw CardIoException(
        type: CardIoErrorType.authFailed,
        message: 'HINATA Mifare authentication failed $keyType',
        originalError: e,
      );
    }
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    try {
      final res = await pn532.mifareClassicReadBlock(tg, block);
      if (res == null) {
        throw CardIoException(
          type: CardIoErrorType.readError,
          message: 'Failed to read Mifare block $block',
        );
      }
      return Uint8List.fromList(res);
    } catch (e) {
      throw CardIoException(
        type: CardIoErrorType.readError,
        message: 'HINATA Mifare read failed',
        originalError: e,
      );
    }
  }

  @override
  Future<void> reconnect() async {
    // PN532 will put Mifare cards in HALT state after a failed Mifare auth.
    // We send an inListPassiveTarget(brty=0, maxTg=1) to reactivate the ISO14443A card.
    await pn532.inListPassiveTarget(0, 1, []);
  }

  @override
  Future<void> close() async {
    await pn532.inRelease(tg);
  }
}
