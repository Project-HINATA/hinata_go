import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../protocol/pn532.dart';
import '../protocol/sega_protocol.dart';
import 'hardware_config.dart';
import 'subscription.dart';
import '../transport/hid_bridge/hid_bridge.dart';

const vendorId = 0xF822;

enum DeviceState { notPaired, paired, connected }

class HinataReader {
  final HIDDevice _device;

  int firmTimeStamp = 0;

  /// Whether the firmware passes PN532 frames longer than one HID report,
  /// split over several.
  bool pn532LongFrames = false;

  /// Whether the firmware accepts two chained PN532 frames in one `0xEC`
  /// report, sending the second once the first one's response is in.
  bool pn532Chain = false;
  List<int> commitHash = [];
  List<int> chipId = [];

  final Map<int, Subscription> _subscriptions = {};

  HinataReader(this._device) {
    _device.onInputReport(_onInputReport);
  }

  int get pid => _device.productId;

  String get firmVersion {
    var version = firmTimeStamp.toString();
    if (firmTimeStamp >= 2025051301) {
      version += "-${_bytesToHex(commitHash)}";
    }
    return version;
  }

  String get chipIdStr {
    var str = "00000000";
    if (firmTimeStamp >= 2025051301) {
      str = _bytesToHex(chipId);
    }
    return str;
  }

  String get productName {
    return _device.productName;
  }

  int segaBrightness = 255;
  Config0 config0 = Config0.fromByte(0x88);
  Color idleRGB = const Color.fromARGB(0, 255, 255, 255);
  Color busyRGB = const Color.fromARGB(0, 0, 0, 255);

  Future open() async {
    if (!_device.opened) {
      await _device.open();
    }
    firmTimeStamp = await getFirmTimeStamp();
    if (firmTimeStamp > 2025040400) {
      commitHash = await getCommitHash();
    }
    if (firmTimeStamp >= 2025051301) {
      chipId = await getChipId();
    }
    if (firmTimeStamp >= 2025100522) {
      await _loadStartupConfig();
    }
    if (firmTimeStamp >= _featuresSince) {
      final features = await _getFeatures();
      pn532LongFrames = features & _featurePn532LongFrames != 0;
      pn532Chain = features & _featurePn532Chain != 0;
    }
  }

  /// The first firmware that answers kPCPROTO_GET_FEATURES.
  static const _featuresSince = 2026110220;
  static const _featurePn532LongFrames = 0x01;
  static const _featurePn532Chain = 0x02;

  /// PN532 bytes one passthrough report carries after its command byte.
  static const _pn532Chunk = 62;
  static const _pn532ChainMax = 48;

  /// The feature bitmask reported by the firmware, or 0 when unsupported.
  Future<int> _getFeatures() async {
    try {
      final data = await sendReq(0xE7, [], timeout: 300);
      return data.length > 1 ? data[1] : 0;
    } catch (_) {
      return 0;
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
      _pn532Sub = _subscribe(0xE2, UnSubscribePolicy.never());
      if (!pn532LongFrames) {
        await sendReqWithoutRes(0xE2, data);
        return;
      }
      // A longer frame continues in kPCPROTO_NFC_PASSTHROUGH_MORE reports,
      // each with its byte count.
      await sendReqWithoutRes(0xE2, data.take(_pn532Chunk).toList());
      for (var i = _pn532Chunk; i < data.length; i += _pn532Chunk - 1) {
        final part = data.skip(i).take(_pn532Chunk - 1).toList();
        await sendReqWithoutRes(0xEB, [part.length, ...part]);
      }
    },
    ({timeout}) async {
      Future<List<int>> next() async {
        final report = _pn532Sub!.receive();
        final res = await (timeout == null ? report : report.timeout(timeout));
        return res.sublist(1);
      }

      var frame = await next();
      // A frame longer than one report continues in the reports after it.
      if (pn532LongFrames) {
        final length = _pn532FrameLength(frame);
        while (frame.length < length) {
          frame = [...frame, ...await next()];
        }
      }
      return frame;
    },
    writeChain: (first, second) async {
      if (!pn532Chain ||
          first.length + second.length > _pn532Chunk ||
          second.length > _pn532ChainMax) {
        return false;
      }
      _pn532Sub = _subscribe(0xE2, UnSubscribePolicy.never());
      await sendReqWithoutRes(0xEC, [...first, ...second]);
      return true;
    },
    onComplete: _clearPn532Subscription,
  );

  /// The bytes of the PN532 frame [frame] starts, through its data
  /// checksum; the postamble may be left out. An ACK is six bytes.
  static int _pn532FrameLength(List<int> frame) {
    if (frame.length < 5 ||
        frame[0] != 0 ||
        frame[1] != 0 ||
        frame[2] != 0xFF) {
      return frame.length;
    }
    if (frame[3] == 0 && frame[4] == 0xFF) return 6;
    return frame[3] + 6;
  }

  void _clearPn532Subscription() {
    final subscription = _pn532Sub;
    if (subscription == null) return;

    if (_subscriptions[0xE2] == subscription) {
      _subscriptions.remove(0xE2);
    }
    subscription.close();
    _pn532Sub = null;
  }

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

    try {
      return await subscription.receive().timeout(
        Duration(milliseconds: timeout),
      );
    } finally {
      if (_subscriptions[responseHeader] == subscription) {
        _subscriptions.remove(responseHeader);
      }
    }
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

  Future<int> getFirmTimeStamp({int timeout = 1000}) async {
    final data = await sendReq(1, [], timeout: timeout, getTimeStamp: true);
    final versionStr = String.fromCharCodes(data);
    final sub = versionStr.substring(0, 10);
    final version = int.parse(sub);
    return version;
  }

  Future<List<int>> getCommitHash({int timeout = 1000}) async {
    final data = await sendReq(0xE5, [], timeout: timeout);
    return data.sublist(1, 5);
  }

  Future<List<int>> getChipId({int timeout = 1000}) async {
    final data = await sendReq(0xE6, [], timeout: timeout);
    return data.sublist(1, 5);
  }

  Future<int> getConfig(ConfigIndex idx, {int timeout = 1000}) async {
    final data = await sendReq(0xD4, [idx.toInt()], timeout: timeout);
    return data[1];
  }

  Future<int> getStorage(ConfigIndex idx, {int timeout = 1000}) async {
    final data = await sendReq(0xD1, [idx.toInt()], timeout: timeout);
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

  Future<void> _loadStartupConfig() async {
    segaBrightness = await getConfig(ConfigIndex.segaBrightness);
    final config0Value = await getConfig(ConfigIndex.config0);
    config0 = Config0.fromByte(config0Value);

    final idleR = await getStorage(ConfigIndex.idleR);
    final idleG = await getStorage(ConfigIndex.idleG);
    final idleB = await getStorage(ConfigIndex.idleB);
    idleRGB = Color.fromARGB(255, idleR, idleG, idleB);

    final busyR = await getStorage(ConfigIndex.busyR);
    final busyG = await getStorage(ConfigIndex.busyG);
    final busyB = await getStorage(ConfigIndex.busyB);
    busyRGB = Color.fromARGB(255, busyR, busyG, busyB);
  }

  Future<void> close() async {
    _device.onInputReport(null);
    await _device.close();
  }

  void destroy() {
    _device.onInputReport(null);
    unawaited(_device.close());
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
