import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

import 'device_interface.dart';
import 'package:hinata_go/models/card/invalid_mifare.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import '../nfc/card_reader_engine.dart';

class UsbHinataDeviceImpl implements DeviceInterface {
  static const Duration _readFailureConfirmWindow = Duration(seconds: 1);

  final HinataReader _hinata;
  final ValueNotifier<DeviceConnectionState> _connectionState = ValueNotifier(
    DeviceConnectionState.disconnected,
  );

  final StreamController<List<int>> _cardioStreamController =
      StreamController<List<int>>.broadcast();

  _PendingReadFailure? _pendingReadFailure;
  _PendingReadFailure? _confirmedReadFailure;
  dynamic _activeTag;

  UsbHinataDeviceImpl(this._hinata) {
    _hinata.subscribeCardioInput((data) {
      if (!_cardioStreamController.isClosed) {
        _cardioStreamController.add(data);
      }
    });

    // Check if initially opened
    // Note: HinataReader object is instantiated when device is connected physically in Provider originally.
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
  Future<ScannedCard?> poll({bool readExtended = true}) async {
    final channel = HinataNfcCardChannel(_hinata.pn532Api);
    final engine = CardReaderEngine(channel);

    for (int i = 0; i < 5; i++) {
      final felicaTag = await _pollFelicaTag();
      if (felicaTag != null) {
        _clearReadFailureState();
        _activeTag = felicaTag;
        return await engine.processTag(
          felicaTag,
          source: 'HINATA',
          readExtended: readExtended,
        );
      }
    }

    final isoTag = await _pollIsoTag();
    if (isoTag != null) {
      _activeTag = isoTag;
      final scanned = await engine.processTag(
        isoTag,
        source: 'HINATA',
        readExtended: readExtended,
      );
      return _resolveReaderScan(scanned);
    }

    _activeTag = null;
    _clearReadFailureState();
    return null;
  }

  @override
  Future<ScannedCard?> readExtended(ScannedCard basicCard) async {
    final tag = _activeTag;
    if (tag == null) {
      return null;
    }

    final channel = HinataNfcCardChannel(_hinata.pn532Api);
    final engine = CardReaderEngine(channel);

    final scanned = await engine.processTag(
      tag,
      source: 'HINATA',
      readExtended: true,
    );
    return _resolveReaderScan(scanned);
  }

  ScannedCard? _resolveReaderScan(ScannedCard? scannedCard) {
    final card = scannedCard?.card;
    if (scannedCard == null || card is! InvalidMifareCard) {
      _clearReadFailureState();
      return scannedCard;
    }

    if (card.reason != InvalidMifareReason.readFailure) {
      _clearReadFailureState();
      return scannedCard;
    }

    final now = DateTime.now();
    final key = _readFailureKey(card);
    final confirmed = _confirmedReadFailure;
    if (confirmed != null && confirmed.key == key) {
      return confirmed.scannedCard;
    }

    final pending = _pendingReadFailure;
    if (pending == null || pending.key != key) {
      _pendingReadFailure = _PendingReadFailure(
        key: key,
        firstSeenAt: now,
        scannedCard: scannedCard,
      );
      return null;
    }

    if (now.difference(pending.firstSeenAt) < _readFailureConfirmWindow) {
      return null;
    }

    _pendingReadFailure = null;
    _confirmedReadFailure = pending;
    return pending.scannedCard;
  }

  String _readFailureKey(InvalidMifareCard card) {
    return '${card.idString}|${card.sak}|${card.atqa}'.toUpperCase();
  }

  void _clearReadFailureState() {
    _pendingReadFailure = null;
    _confirmedReadFailure = null;
  }

  Future<Felica?> _pollFelicaTag() async {
    final initialData = _hinata.pn532Api.genFelicaPollInitialData(
      0xFFFF,
      0x0001,
    );
    final targets = await _hinata.pn532Api.inListPassiveTarget(
      1,
      1,
      initialData,
    );
    if (targets.isNotEmpty) {
      final t = targets[0];
      return Felica(t.id, t.pmm!, t.systemCodes!);
    }
    return null;
  }

  Future<Iso14443?> _pollIsoTag() async {
    final targets = await _hinata.pn532Api.inListPassiveTarget(0, 1, []);
    if (targets.isNotEmpty) {
      final t = targets[0];
      return Iso14443(t.id, t.sak!, t.atqa!);
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

class _PendingReadFailure {
  const _PendingReadFailure({
    required this.key,
    required this.firstSeenAt,
    required this.scannedCard,
  });

  final String key;
  final DateTime firstSeenAt;
  final ScannedCard scannedCard;
}
