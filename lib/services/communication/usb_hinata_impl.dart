import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'device_interface.dart';
import 'package:hinata_go/models/hardware_config.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import '../hardware/core/hinata_device.dart';
import '../nfc/card_reader_engine.dart';
import '../nfc/hinata_transceiver.dart';

class UsbHinataDeviceImpl implements DeviceInterface {
  final HINATA _hinata;
  final ValueNotifier<DeviceConnectionState> _connectionState = ValueNotifier(
    DeviceConnectionState.disconnected,
  );

  final StreamController<List<int>> _cardioStreamController =
      StreamController<List<int>>.broadcast();

  UsbHinataDeviceImpl(this._hinata) {
    _hinata.subscribeCardioInput((data) {
      if (!_cardioStreamController.isClosed) {
        _cardioStreamController.add(data);
      }
    });

    // Check if initially opened
    // Note: HINATA object is instantiated when device is connected physically in Provider originally.
    // So we'll trigger state change on connect.
  }

  @override
  String get deviceId => _hinata.pid.toString();

  @override
  String get productName => _hinata.productName;

  String get firmVersion => _hinata.firmVersion;
  int get productId => _hinata.pid;
  Config0 get config0 => _hinata.config0;
  Color get idleRGB => _hinata.idleRGB;
  set idleRGB(Color color) => _hinata.idleRGB = color;

  Color get busyRGB => _hinata.busyRGB;
  set busyRGB(Color color) => _hinata.busyRGB = color;

  int get segaBrightness => _hinata.segaBrightness;
  set segaBrightness(int brightness) => _hinata.segaBrightness = brightness;

  @override
  ValueNotifier<DeviceConnectionState> get connectionState => _connectionState;

  @override
  Stream<List<int>> get cardioInputStream => _cardioStreamController.stream;

  @override
  Future<void> connect() async {
    _connectionState.value = DeviceConnectionState.connecting;
    try {
      await _hinata.open();
      _connectionState.value = DeviceConnectionState.connected;
    } catch (e) {
      _connectionState.value = DeviceConnectionState.error;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _hinata.close();
    _connectionState.value = DeviceConnectionState.disconnected;
  }

  @override
  Future<void> enterBootloader() async {
    _hinata.enterBootloader();
  }

  @override
  Future<void> setLed(Color color) async {
    await _hinata.setLed(color);
  }

  @override
  Future<int> getFirmTimeStamp() async {
    return await _hinata.getFirmTimeStamp();
  }

  @override
  Future<List<int>> getChipId() async {
    return await _hinata.getChipId();
  }

  @override
  Future<void> setConfig(int index, int value) async {
    await _hinata.setConfig(ConfigIndex.values[index], value);
  }

  @override
  Future<int> getConfig(int index) async {
    return await _hinata.getConfig(ConfigIndex.values[index]);
  }

  Future<void> setStorage(ConfigIndex index, int value) async {
    await _hinata.setStorage(index, value);
  }

  Future<int> getStorage(ConfigIndex index) async {
    return await _hinata.getStorage(index);
  }

  Future<void> reloadConfig() async {
    await _hinata.reloadConfig();
  }

  Future<void> resetLed() async {
    await _hinata.resetLed();
  }

  @override
  Future<ScannedCard?> poll() async {
    final transceiver = HinataTransceiver(_hinata.pn532Api);
    final engine = CardReaderEngine(transceiver);

    for (int i = 0; i < 5; i++) {
      final felicaTag = await _pollFelicaTag();
      if (felicaTag != null) {
        return await engine.processTag(felicaTag, source: 'HINATA');
      }
    }

    final isoTag = await _pollIsoTag();
    if (isoTag != null) {
      return await engine.processTag(isoTag, source: 'HINATA');
    }

    return null;
  }

  Future<Felica?> _pollFelicaTag() async {
    final initialData = _hinata.pn532Api.genFelicaPollInitialData(
      0xFFFF,
      0x0001,
    );
    final cards = await _hinata.pn532Api.inListPassiveTarget(1, 1, initialData);
    if (cards.isNotEmpty && cards[0] is Felica) {
      return cards[0] as Felica;
    }
    return null;
  }

  Future<Iso14443?> _pollIsoTag() async {
    final cards = await _hinata.pn532Api.inListPassiveTarget(0, 1, []);
    if (cards.isNotEmpty && cards[0] is Iso14443) {
      return cards[0] as Iso14443;
    }
    return null;
  }

  @override
  Future<List<int>> sendCommand(
    int command,
    List<int> payload, {
    int timeoutMs = 1000,
  }) async {
    return await _hinata.sendReq(command, payload, timeout: timeoutMs);
  }

  @override
  void dispose() {
    _cardioStreamController.close();
    _hinata.destroy();
  }
}
