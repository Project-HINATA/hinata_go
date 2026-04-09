import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:hinata_go/services/hardware/protocols/base.dart';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
// Removed hex_string_to_list import

enum Pn532Error {
  none(0x00),
  timeout(0x01),
  crc(0x02),
  parity(0x03),
  collisionBitCount(0x04),
  mifareFraming(0x05),
  collisionBitCollision(0x06),
  noBufs(0x07),
  rfNoBufs(0x09),
  activeTooSlow(0x0a),
  rfProto(0x0b),
  tooHot(0x0d),
  internalNoBufs(0x0e),
  inval(0x10),
  depInvalidCommand(0x12),
  depBadData(0x13),
  mifareAuth(0x14),
  noSecure(0x18),
  i2cBusy(0x19),
  uidChecksum(0x23),
  depState(0x25),
  hciInval(0x26),
  context(0x27),
  released(0x29),
  cardSwapped(0x2a),
  noCard(0x2b),
  mismatch(0x2c),
  overCurrent(0x2d),
  noNad(0x2e),
  unknown(0xFF);

  final int value;
  const Pn532Error(this.value);

  static Pn532Error fromValue(int value) {
    return Pn532Error.values.firstWhere(
      (e) => e.value == value,
      orElse: () => Pn532Error.unknown,
    );
  }

  int toInt() => value;
}

enum Pn532Command {
  diagnose(0x00),
  getFirmwareVersion(0x02),
  getGeneralStatus(0x04),
  readRegister(0x06),
  writeRegister(0x08),
  readGpio(0x0C),
  writeGpio(0x0E),
  setSerialBaudRate(0x10),
  setParameters(0x12),
  samConfiguration(0x14),
  powerDown(0x16),
  rfConfiguration(0x32),
  rfRegulationTest(0x58),
  inJumpForDep(0x56),
  inJumpForPsl(0x46),
  inListPassiveTarget(0x4A),
  inAtr(0x50),
  inPsl(0x4E),
  inDataExchange(0x40),
  inCommunicateThru(0x42),
  inDeselect(0x44),
  inRelease(0x52),
  inSelect(0x54),
  inAutoPoll(0x60),
  tgInitAsTarget(0x8C),
  tgSetGeneralBytes(0x92),
  tgGetData(0x86),
  tgSetData(0x8E),
  tgSetMetaData(0x94),
  tgGetInitiatorCommand(0x88),
  tgResponseToInitiator(0x90),
  tgGetTargetStatus(0x8A),
  empty(0xFE);

  final int value;
  const Pn532Command(this.value);

  /// 从整数获取对应的枚举值
  static Pn532Command? fromValue(int value) {
    try {
      return Pn532Command.values.firstWhere((e) => e.value == value);
    } catch (_) {
      return null;
    }
  }

  /// 获取枚举值的整数形式
  int toInt() => value;
}

enum MifareCommand {
  authA(0x60),
  authB(0x61),
  read(0x30),
  write(0xA0),
  transfer(0xB0),
  decrement(0xC0),
  increment(0xC1),
  store(0xC2),
  ultralightWrite(0xA2),
  unknown(0xFF);

  final int value;
  const MifareCommand(this.value);

  static MifareCommand fromValue(int value) {
    return MifareCommand.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MifareCommand.unknown,
    );
  }

  int toInt() => value;
}

enum FelicaCommand {
  polling(0x00),
  requestService(0x02),
  requestResponse(0x04),
  readWithoutEncryption(0x06),
  writeWithoutEncryption(0x08),
  requestSystemCode(0x0C),
  unknown(0xFF);

  final int value;
  const FelicaCommand(this.value);

  static FelicaCommand fromValue(int value) {
    return FelicaCommand.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FelicaCommand.unknown,
    );
  }

  int toInt() => value;
}

class Pn532Packet {
  final int direction;
  final Pn532Command command;
  final List<int> payload;

  Pn532Packet({
    required this.direction,
    required this.command,
    required this.payload,
  });

  static Pn532Packet fromList(List<int> data) {
    if (data[0] != 0x00 || data[1] != 0x00 || data[2] != 0xFF) {
      throw Exception('Invalid preamble');
    }
    final payloadLen = data[3];
    if ((payloadLen + data[4]) & 0xFF != 0) {
      log("Invalid length checksum: $data");
      throw Exception('Invalid length checksum');
    }
    if (data[5] != 0xD4 && data[5] != 0xD5) {
      throw Exception('Invalid direction');
    }
    var checksum = data[5];
    for (var i = 6; i < 5 + payloadLen; i++) {
      checksum += data[i];
    }
    var cmd = Pn532Command.fromValue(data[6] - 1);
    if (cmd == null) {
      throw Exception('Invalid command');
    }
    var payload = data.sublist(7, 5 + payloadLen);
    if ((checksum + data[5 + payloadLen]) & 0xFF != 0) {
      throw Exception('Invalid checksum: $checksum, ${data[5 + payloadLen]}');
    }
    return Pn532Packet(direction: data[5], command: cmd, payload: payload);
  }

  List<int> toList() {
    var len = 2 + payload.length;
    var buffer = [
      0, 0, 0xFF, // PREAMBLE & STARTCODE
      len, (~len & 0xFF) + 1, // LENGTH & LENGTH CHECKSUM
      direction, // DIRECTION
      command.toInt(), // COMMAND
    ];
    buffer.addAll(payload);
    int checksum = command.toInt() + direction;
    for (var i = 0; i < payload.length; i++) {
      checksum += payload[i];
    }
    checksum = (~checksum & 0xFF) + 1;
    buffer.add(checksum);
    buffer.add(0x00); // ENDING CHECKSUM
    return buffer;
  }
}

const int mifareUidSingleLength = 4;
const int mifareUidDoubleLength = 7;
const int mifareUidTripleLength = 10;
const int mifareUidMaxLength = mifareUidTripleLength;
const int mifareKeyLength = 6;
const int mifareBlockLength = 16;
const standardAck = [0, 0, 0xFF, 0, 0xFF, 0];

class Pn532Api extends IoBase {
  Future<Pn532Packet> _sendAndReceive(
    Pn532Command command,
    List<int> payload, {
    int timeout = 100,
  }) async {
    var packet = Pn532Packet(
      direction: 0xD4,
      command: command,
      payload: payload,
    );
    try {
      await write(packet.toList());

      final effectiveTimeout = Duration(milliseconds: timeout);

      List<int>? data;

      List<List<int>> cache = [];
      int count = 0;

      while (true) {
        List<int>? res;
        try {
          count++;
          res = await read(timeout: effectiveTimeout);
          cache.add(res);
          log("PN532 Stream: $count: $res");
        } catch (e) {
          log("PN532 Stream warn: $e");
          break;
        }
        if (res[3] == 0 && res[4] == 0xFF) {
          continue;
        } else if ((res[3] + res[4]) & 0xFF != 0) {
          throw Exception("Invalid PN532 length checksum");
        }
        if (res[3] > 0) {
          data = res;
          break;
        }
      }
      if (data != null) {
        return Pn532Packet.fromList(data);
      }
      log(cache.toString());
      throw Exception("No response from PN532");
    } catch (e) {
      log("PN532 Error: $e");
      return Pn532Packet(
        direction: 0xD5,
        command: Pn532Command.empty,
        payload: [],
      );
    }
  }

  Future<List<ICCard>> inListPassiveTarget(
    int brty,
    int maxTg,
    List<int> initialData,
  ) async {
    var payload = [maxTg, brty];
    payload.addAll(initialData);
    final res = await _sendAndReceive(
      Pn532Command.inListPassiveTarget,
      payload,
    );
    if (res.command == Pn532Command.empty) return [];
    if (res.payload.isEmpty) {
      log('PN532 inListPassiveTarget returned empty payload for brty=$brty');
      return [];
    }
    final tagNum = res.payload[0];
    var tags = <ICCard>[];
    var idIdx = 1;
    for (var i = 0; i < tagNum; i++) {
      switch (brty) {
        case 0: // 106 kbps type A (ISO/IEC14443 Type A)
          // 00, 00, ff, 00, ff, 00, 4b,
          // 02,
          // 01, [00, 44], 00, 07, [04, 86, 25, e2, 94, 1e, 94],
          // 02, [00, 04], 08, 04, [3b, fb, 00, 2d]

          // id1 = 9
          // id2 = 9 + 2 + 1 + 1 + uidLen

          // log("ISO14443-A: ${res.payload}");

          if (res.payload.length < idIdx + 5) {
            log(
              'PN532 ISO14443 payload too short for header: '
              '${res.payload} (idIdx=$idIdx)',
            );
            return tags;
          }

          int atqa =
              res.payload[idIdx + 1] << 8 | res.payload[idIdx + 2]; // ATQA
          int sak = res.payload[idIdx + 3]; // SAK
          int idLen = res.payload[idIdx + 4]; // UID Length
          if (res.payload.length < idIdx + 5 + idLen) {
            log(
              'PN532 ISO14443 payload too short for UID: '
              '${res.payload} (idIdx=$idIdx, idLen=$idLen)',
            );
            return tags;
          }
          var id = res.payload.sublist(idIdx + 5, idIdx + 5 + idLen); // UID
          idIdx += 5 + idLen;
          tags.add(Iso14443(Uint8List.fromList(id), sak, atqa));
        case 1: // 212 kbps (FeliCa polling)
        case 2: // 424 kbps (FeliCa polling)
          // 00, 00, ff, 18, e8, d5, 4b,
          // 01,
          // 01, 14, 01, [01, 2e, 55, 14, e4, 08, 83, 40], [00, f1, 00, 00, 00, 01, 43, 00], [88, b4]

          // 2: Length
          // 3: Id of two
          // 4 ~ 4 + 8: Idm
          // 4+8 ~ 4+8+8 Pmm
          // 4+8+8 ~ 4+8+8+ 2 * n: SystemCode
          if (res.payload.length < 16) return [];
          var packetLen = res.payload[idIdx + 1];
          var systemCodesCount = (packetLen - 2 - 8 - 8) >> 1;

          var idm = res.payload.sublist(idIdx + 3, idIdx + 11);
          var pmm = res.payload.sublist(idIdx + 11, idIdx + 19);
          var systemCodes = <int>[];
          for (var j = 0; j < systemCodesCount; j++) {
            var systemCode =
                (res.payload[idIdx + 20 + j * 2 - 1] << 8) |
                (res.payload[idIdx + 20 + j * 2]);
            systemCodes.add(systemCode);
          }
          idIdx += 20 + systemCodesCount * 2;
          tags.add(
            Felica(
              Uint8List.fromList(idm),
              Uint8List.fromList(pmm),
              Uint16List.fromList(systemCodes),
            ),
          );
        case 3: // 106 kbps type B (ISO/IEC14443-3B)
        case 4: // 106 kbps Innovision Jewel tag.
        default:
          break;
      }
    }

    return tags;
  }

  Future<List<int>> inDataExchange(int tg, int cmd, List<int> data) async {
    var payload = [tg, cmd, ...data];
    final res = await _sendAndReceive(Pn532Command.inDataExchange, payload);
    if (res.command == Pn532Command.empty) return [-1];
    return res.payload;
  }

  List<int> genFelicaPollInitialData(int systemCode, int requestCode) {
    return [
      FelicaCommand.polling.toInt(),
      (systemCode >> 8) & 0xFF,
      systemCode & 0xFF,
      requestCode,
      0,
    ];
  }

  Future<Pn532Error> mifareClassicAuth(
    int tg,
    List<int> uid,
    int blockNum,
    int keyNum,
    List<int> key,
  ) async {
    var input = [blockNum];
    input.addAll(key.sublist(0, 6));
    input.addAll(uid);
    final res = await inDataExchange(tg, keyNum, input);
    return Pn532Error.fromValue(res[0]);
  }

  Future<int> mifareClassicWriteBlock(
    int tg,
    int blockNum,
    List<int> blockData,
  ) async {
    var input = [blockNum];
    input.addAll(blockData.sublist(0, 16));
    final res = await inDataExchange(tg, MifareCommand.write.toInt(), input);
    return res[0];
  }

  Future<List<int>?> mifareClassicReadBlock(int tg, int blockNum) async {
    var input = [blockNum];
    final res = await inDataExchange(tg, MifareCommand.read.toInt(), input);
    if (res[0] == 0 && res.length > 16) {
      return res.sublist(1, 1 + 16);
    } else {
      return null;
    }
  }

  Future<Pn532Error> inRelease(int tg) async {
    var input = [tg];
    final res = await _sendAndReceive(Pn532Command.inRelease, input);
    return Pn532Error.fromValue(res.payload[0]);
  }

  Future<Pn532Error> inSelect(int tg, List<int> uid) async {
    var input = [tg];
    input.addAll(uid);
    final res = await _sendAndReceive(Pn532Command.inSelect, input);
    return Pn532Error.fromValue(res.payload[0]);
  }

  Future<Pn532Error> inDeselect(int tg) async {
    var input = [tg];
    final res = await _sendAndReceive(Pn532Command.inDeselect, input);
    return Pn532Error.fromValue(res.payload[0]);
  }

  Future setRfCfg(int autoRFCA, int rFOnOff) async {
    await rfConfiguration(1, [0 | autoRFCA | rFOnOff]);
  }

  Future rfConfiguration(int cfgItem, List<int> payload) async {
    var input = [cfgItem];
    input.addAll(payload);
    await _sendAndReceive(Pn532Command.rfConfiguration, input);
  }

  Future<int> getFirmwareVersion() async {
    final res = await _sendAndReceive(Pn532Command.getFirmwareVersion, <int>[]);
    if (res.command == Pn532Command.empty) return -1;
    if (res.payload.length < 2) return -1;
    log("firmware version: ${res.payload[0]} ${res.payload[1]}");
    return (res.payload[0] << 8) | res.payload[1];
  }

  Uint8List uint16ListToUint8List(Uint16List uint16List) {
    final byteBuffer = ByteData(uint16List.length * 2);
    for (int i = 0; i < uint16List.length; i++) {
      byteBuffer.setUint16(i * 2, uint16List[i], Endian.big);
    }
    return byteBuffer.buffer.asUint8List();
  }

  Future<List<int>?> felicaReadWithoutEncryption(
    int tg,
    Uint8List idm,
    Uint16List services,
    Uint16List blocks,
  ) async {
    var input = [FelicaCommand.readWithoutEncryption.toInt()];
    input.addAll(idm.toList().sublist(0, 8));
    input.add(services.length);
    input.addAll(uint16ListToUint8List(services).toList());
    input.add(blocks.length);
    input.addAll(uint16ListToUint8List(blocks).toList());
    final res = await inDataExchange(tg, input.length + 1, input);
    return res;
  }

  Pn532Api(super.write, super.read);
}
