import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hinata_go/utils/hex_utils.dart';

import 'package:hinata_go/services/hardware/protocols/pn532.dart';
import 'package:hinata_go/models/hardware_config.dart';
import 'package:hinata_go/services/hardware/core/subscription.dart';
import 'package:hinata_go/services/hardware/transport/hid_bridge/hid_bridge.dart';
import 'package:hinata_go/services/hardware/protocols/sega_protocol.dart';

const vendorId = 0xF822;

enum DeviceState { notPaired, paired, connected }

class HINATA {
  final HIDDevice _device;

  int firmTimeStamp = 0;
  List<int> commitHash = [];
  List<int> chipId = [];

  final Map<int, Subscription> _subscriptions = {};

  HINATA(this._device) {
    _device.onInputReport(_onInputReport);
  }

  int get pid => _device.productId;

  String get firmVersion {
    var version = firmTimeStamp.toString();
    if (firmTimeStamp >= 2025051301) {
      version += "-${HexUtils.bytesToHex(commitHash)}";
    }
    return version;
  }

  String get chipIdStr {
    var str = "00000000";
    if (firmTimeStamp >= 2025051301) {
      str = HexUtils.bytesToHex(chipId);
    }
    return str;
  }

  String get productName {
    return _device.productName;
  }

  int segaBrightness = 255;
  Config0 config0 = Config0.fromByte(0x88);
  Color idleRGB = Color.fromARGB(0, 255, 255, 255);
  Color busyRGB = Color.fromARGB(0, 0, 0, 255);

  Future open() async {
    if (!_device.opened) {
      await _device.open().catchError((e) {}).onError((e, s) {});
    }
    firmTimeStamp = await getFirmTimeStamp();
    if (firmTimeStamp > 2025040400) commitHash = await getCommitHash();
    if (firmTimeStamp >= 2025051301) chipId = await getChipId();
    if (firmTimeStamp >= 2025100522) {
      segaBrightness = await getConfig(ConfigIndex.segaBrightness);
      config0 = Config0.fromByte(await getConfig(ConfigIndex.config0));
      idleRGB = Color.fromARGB(
        255,
        await getStorage(ConfigIndex.idleR),
        await getStorage(ConfigIndex.idleG),
        await getStorage(ConfigIndex.idleB),
      );
      busyRGB = Color.fromARGB(
        255,
        await getStorage(ConfigIndex.busyR),
        await getStorage(ConfigIndex.busyG),
        await getStorage(ConfigIndex.busyB),
      );
    }
  }

  Subscription? _segaSub;
  late final segaApi = SegaApi(
    (data) async {
      _segaSub = _subscribe(0xE0, UnSubscribePolicy.count(1));
      await sendReqWithoutRes(0xE0, data);
    },
    ({timeout}) => _segaSub!.receive().timeout(
      timeout ?? const Duration(milliseconds: 1000),
    ),
  );

  Subscription? _pn532Sub;
  late final pn532Api = Pn532Api(
    (data) async {
      _pn532Sub = _subscribe(0xE2, UnSubscribePolicy.specificNotOn(4, 0));
      await sendReqWithoutRes(0xE2, data);
    },
    ({timeout}) async {
      var res = await _pn532Sub!.receive().timeout(
        timeout ?? const Duration(milliseconds: 2000),
      );
      return res.sublist(1);
    },
  );

  List<List<int>> cardIOData = List.empty(growable: true);
  Function(List<int> cardIOData)? _cardioCallback;

  var count = 0;
  void _onInputReport(HIDInputReportEvent event) {
    var reportId = event.reportId;

    if (reportId == 2) {
      var data = event.data.buffer.asUint8List(0, 8);
      if (_cardioCallback != null) {
        _cardioCallback!(data);
      }
    } else {
      var data = event.data.buffer.asUint8List(0);
      var header = data[0];
      if (_subscriptions.containsKey(header)) {
        if (_subscriptions[header]!.send(data)) {
          _subscriptions.remove(header);
        }
      }
    }
  }

  void subscribeCardioInput(dynamic Function(List<int> cardIOData) callback) {
    log("toggle callback");
    _cardioCallback = callback;
  }

  Subscription _subscribe(int header, UnSubscribePolicy policy) {
    final subscription = Subscription(policy);
    _subscriptions[header] = subscription;
    return subscription;
  }

  Future<List<int>> sendReq(
    int command,
    List<int> sendData, {
    int timeout = 1000,
    bool getTimeStamp = false,
  }) async {
    int responseHeader = command;
    if (command == 1) {
      responseHeader = 0x32;
    }

    final subscription = _subscribe(responseHeader, UnSubscribePolicy.count(1));

    var buffer = List<int>.from(sendData);
    buffer.insert(0, command);
    final data = Uint8List.fromList(buffer);
    await _device.sendReport(1, data.buffer.asByteData(0));

    return subscription.receive().timeout(Duration(milliseconds: timeout));
  }

  Future sendReqWithoutRes(int command, List<int> sendData) async {
    var buffer = List<int>.from(sendData);
    buffer.insert(0, command);
    final data = Uint8List.fromList(buffer);
    await _device.sendReport(1, data.buffer.asByteData(0));
  }

  Future<void> setLed(Color color) async {
    await sendReqWithoutRes(7, [
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
    ]);
  }

  void enterBootloader() async {
    await sendReqWithoutRes(0xf0, []);
  }

  Future<int> getFirmTimeStamp() async {
    final data = await sendReq(1, [], getTimeStamp: true);
    final versionStr = String.fromCharCodes(data);
    final sub = versionStr.substring(0, 10);
    final version = int.parse(sub);
    return version;
  }

  Future<List<int>> getCommitHash() async {
    final data = await sendReq(0xE5, []);
    return data.sublist(1, 5);
  }

  Future<List<int>> getChipId() async {
    final data = await sendReq(0xE6, []);
    return data.sublist(1, 5);
  }

  Future<int> getConfig(ConfigIndex idx) async {
    final data = await sendReq(0xD4, [idx.toInt()]);
    return data[1];
  }

  Future<int> getStorage(ConfigIndex idx) async {
    final data = await sendReq(0xD1, [idx.toInt()]);
    return data[1];
  }

  Future<void> setConfig(ConfigIndex idx, int value) async {
    await sendReqWithoutRes(0xD3, [idx.toInt(), value]);
  }

  Future<void> setStorage(ConfigIndex idx, int value) async {
    await sendReqWithoutRes(0xD0, [idx.toInt(), value]);
  }

  Future<void> resetStateMachine() async {
    await sendReqWithoutRes(0xE8, []);
  }

  Future<void> reloadConfig() async {
    await sendReqWithoutRes(0xE9, []);
  }

  Future<void> resetLed() async {
    await sendReqWithoutRes(0xEA, []);
  }

  Future<int> getMainLoopState() async {
    var res = await sendReq(0xE3, []);
    return res[1];
  }

  Future<void> close() async {
    _device.onInputReport(null);
    await _device.close();
  }

  void destroy() {
    _device.onInputReport(null);
    unawaited(_device.close());
  }
}
