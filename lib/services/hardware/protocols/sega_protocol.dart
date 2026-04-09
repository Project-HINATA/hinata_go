import 'dart:async';
import 'dart:typed_data';

import 'package:hinata_go/services/hardware/protocols/base.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';

enum ResponseCode {
  ok(0x00),
  cardError(0x01),
  noAccept(0x02),
  invalidCommand(0x03),
  invalidData(0x04),
  sumError(0x05),
  asicError(0x06),
  hexError(0x07),
  sendFin(0x08),
  isNewReader(0x10),
  isNewReader3(0x20),
  unknown(0xFF);

  final int value;
  const ResponseCode(this.value);

  static ResponseCode fromValue(int value) {
    return ResponseCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ResponseCode.unknown,
    );
  }

  int toInt() => value;
}

enum NFCCommand {
  getFwVersion(0x30),
  getHwVersion(0x32),
  startPolling(0x40),
  stopPolling(0x41),
  cardDetect(0x42),
  cardSelect(0x43),
  cardHalt(0x44),
  mifareKeySetA(0x50),
  mifareAuthorizeA(0x51),
  mifareRead(0x52),
  mifareWrite(0x53),
  mifareKeySetB(0x54),
  mifareAuthorizeB(0x55),
  toUpdaterMode(0x60),
  sendHexData(0x61),
  toNormalMode(0x62),
  sendBinDataInit(0x63),
  sendBinDataExec(0x64),
  felicaPush(0x70),
  nfcThrough(0x71),
  extBoardLed(0x80),
  extBoardLedRgb(0x81),
  extBoardLedThinca(0x82),
  extBoardInfo(0xF0),
  extFirmSum(0xF2),
  extSendHexData(0xF3),
  extToBootMode(0xF4),
  extToNormalMode(0xF5),
  unknown(0xFF);

  final int value;
  const NFCCommand(this.value);

  static NFCCommand fromValue(int value) {
    return NFCCommand.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NFCCommand.unknown,
    );
  }

  int toInt() => value;
}

class SegaApi extends IoBase {
  int packetSequence = 0;
  Future<List<int>> _send(
    NFCCommand command,
    List<int> payload, {
    int timeout = 1000,
  }) async {
    packetSequence++;

    var buffer = [
      payload.length + 5,
      0,
      packetSequence & 0xFF,
      command.toInt(),
      payload.length,
    ];
    buffer.addAll(payload);

    await write(buffer);
    return await read(timeout: Duration(milliseconds: timeout));
  }

  Future<int> startPoll() async {
    final res = await _send(NFCCommand.startPolling, []);
    return res[5];
  }

  Future<int> stopPoll() async {
    final res = await _send(NFCCommand.stopPolling, []);
    return res[5];
  }

  Future<ICCard?> detectCard() async {
    final res = await _send(NFCCommand.cardDetect, []);
    final cardNum = res[7];
    if (cardNum == 1) {
      final cardType = res[8];
      final idLen = res[9];
      if (cardType == 0x10) {
        return Felica(
          Uint8List.fromList(res.sublist(10, 10 + 8)),
          Uint8List.fromList(res.sublist(10 + 8, 10 + 8 + 8)),
          Uint16List.fromList([0xFFFF]),
        );
      }
      if (cardType == 0x20) {
        return Iso14443(
          Uint8List.fromList(res.sublist(10, 10 + idLen)),
          0x08,
          0x0000,
        );
      }
    }
    return null;
  }

  SegaApi(super.write, super.read);
}
