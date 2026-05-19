import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../card/card_tag.dart';
import '../card/card_transceiver.dart';
import '../core/subscription.dart';
import 'hinata_card_transceiver.dart';
import '../protocols/pn532.dart';
import '../protocols/sega_protocol.dart';
import '../transport/hid_bridge/hid_bridge.dart';
import 'hinata_config.dart';

const hinataVendorId = 0xF822;

enum DeviceState { notPaired, paired, connected }

enum ReaderConnectionState { disconnected, connecting, connected, error }

class HinataReader {
  final HIDDevice _device;
  final ValueNotifier<ReaderConnectionState> connectionState = ValueNotifier(
    ReaderConnectionState.disconnected,
  );
  final StreamController<List<int>> _cardioInputController =
      StreamController<List<int>>.broadcast();

  int firmTimeStamp = 0;
  List<int> commitHash = [];
  List<int> chipId = [];

  final Map<int, Subscription> _subscriptions = {};

  HinataReader(this._device) {
    _device.onInputReport(_onInputReport);
  }

  int get productId => _device.productId;

  String get deviceId => productId.toString();

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

  Stream<List<int>> get cardioInputStream => _cardioInputController.stream;

  int segaBrightness = 255;
  Config0 config0 = Config0.fromByte(0x88);
  Color idleRGB = Color.fromARGB(0, 255, 255, 255);
  Color busyRGB = Color.fromARGB(0, 0, 0, 255);

  Future<void> connect() async {
    connectionState.value = ReaderConnectionState.connecting;
    try {
      await open();
      connectionState.value = ReaderConnectionState.connected;
    } catch (_) {
      connectionState.value = ReaderConnectionState.error;
      rethrow;
    }
  }

  Future open() async {
    if (!_device.opened) {
      await _device.open();
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
      await sendCommandWithoutResponse(0xE0, data);
    },
    ({timeout}) => _segaSub!.receive().timeout(
      timeout ?? const Duration(milliseconds: 1000),
    ),
  );

  Subscription? _pn532Sub;
  late final pn532Api = Pn532Api(
    (data) async {
      _pn532Sub = _subscribe(0xE2, UnSubscribePolicy.specificNotOn(4, 0));
      await sendCommandWithoutResponse(0xE2, data);
    },
    ({timeout}) async {
      var res = await _pn532Sub!.receive().timeout(
        timeout ?? const Duration(milliseconds: 2000),
      );
      return res.sublist(1);
    },
  );

  void _onInputReport(HIDInputReportEvent event) {
    var reportId = event.reportId;

    if (reportId == 2) {
      var data = event.data.buffer.asUint8List(0, 8);
      if (!_cardioInputController.isClosed) {
        _cardioInputController.add(data);
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

  Subscription _subscribe(int header, UnSubscribePolicy policy) {
    final subscription = Subscription(policy);
    _subscriptions[header] = subscription;
    return subscription;
  }

  Future<List<int>> sendCommand(
    int command,
    List<int> payload, {
    int timeout = 1000,
  }) async {
    int responseHeader = command;
    if (command == 1) {
      responseHeader = 0x32;
    }

    final subscription = _subscribe(responseHeader, UnSubscribePolicy.count(1));

    var buffer = List<int>.from(payload);
    buffer.insert(0, command);
    final data = Uint8List.fromList(buffer);
    await _device.sendReport(1, data.buffer.asByteData(0));

    return subscription.receive().timeout(Duration(milliseconds: timeout));
  }

  Future<void> sendCommandWithoutResponse(
    int command,
    List<int> payload,
  ) async {
    var buffer = List<int>.from(payload);
    buffer.insert(0, command);
    final data = Uint8List.fromList(buffer);
    await _device.sendReport(1, data.buffer.asByteData(0));
  }

  Future<void> setLed(Color color) async {
    await sendCommandWithoutResponse(7, [
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
    ]);
  }

  Future<void> enterBootloader() async {
    await sendCommandWithoutResponse(0xf0, []);
  }

  Future<int> getFirmTimeStamp() async {
    final data = await sendCommand(1, []);
    final versionStr = String.fromCharCodes(data);
    final sub = versionStr.substring(0, 10);
    final version = int.parse(sub);
    return version;
  }

  Future<List<int>> getCommitHash() async {
    final data = await sendCommand(0xE5, []);
    return data.sublist(1, 5);
  }

  Future<List<int>> getChipId() async {
    final data = await sendCommand(0xE6, []);
    return data.sublist(1, 5);
  }

  Future<int> getConfig(ConfigIndex idx) async {
    final data = await sendCommand(0xD4, [idx.toInt()]);
    return data[1];
  }

  Future<int> getStorage(ConfigIndex idx) async {
    final data = await sendCommand(0xD1, [idx.toInt()]);
    return data[1];
  }

  Future<void> setConfig(ConfigIndex idx, int value) async {
    await sendCommandWithoutResponse(0xD3, [idx.toInt(), value]);
  }

  Future<void> setStorage(ConfigIndex idx, int value) async {
    await sendCommandWithoutResponse(0xD0, [idx.toInt(), value]);
  }

  Future<void> resetStateMachine() async {
    await sendCommandWithoutResponse(0xE8, []);
  }

  Future<void> reloadConfig() async {
    await sendCommandWithoutResponse(0xE9, []);
  }

  Future<void> resetLed() async {
    await sendCommandWithoutResponse(0xEA, []);
  }

  Future<int> getMainLoopState() async {
    var res = await sendCommand(0xE3, []);
    return res[1];
  }

  CardTransceiver createTransceiver({int target = 1}) {
    return HinataCardTransceiver(pn532Api, tg: target);
  }

  Future<CardTag?> pollCard({int felicaAttempts = 5}) async {
    for (var i = 0; i < felicaAttempts; i++) {
      final felica = await pollFelica();
      if (felica != null) {
        return felica;
      }
    }

    return pollIso14443a();
  }

  Future<FelicaTag?> pollFelica() async {
    final initialData = pn532Api.genFelicaPollInitialData(0xFFFF, 0x0001);
    final cards = await pn532Api.inListPassiveTarget(1, 1, initialData);
    if (cards.isNotEmpty && cards.first is FelicaTag) {
      return cards.first as FelicaTag;
    }
    return null;
  }

  Future<Iso14443aTag?> pollIso14443a() async {
    final cards = await pn532Api.inListPassiveTarget(0, 1, []);
    if (cards.isNotEmpty && cards.first is Iso14443aTag) {
      return cards.first as Iso14443aTag;
    }
    return null;
  }

  Future<void> close() async {
    _device.onInputReport(null);
    await _device.close();
    connectionState.value = ReaderConnectionState.disconnected;
  }

  Future<void> disconnect() => close();

  void dispose() {
    _cardioInputController.close();
    destroy();
  }

  void destroy() {
    _device.onInputReport(null);
    unawaited(_device.close());
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}
