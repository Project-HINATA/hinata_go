import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

import 'device_interface.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import '../nfc/card_reader_engine.dart';

// 完整模拟配置用于覆盖不同卡片与耦合距离。
class TypeARfProfile {
  final int rfCfg;
  final int cwGsNOn;
  final int cwGsP;

  const TypeARfProfile({
    required this.rfCfg,
    required this.cwGsNOn,
    required this.cwGsP,
  });
}

const pn532DefaultTypeARfProfile = TypeARfProfile(
  rfCfg: 0x59,
  cwGsNOn: 0x0F,
  cwGsP: 0x3F,
);

const standardTypeARfProfiles = <TypeARfProfile>[
  pn532DefaultTypeARfProfile,
  TypeARfProfile(rfCfg: 0x69, cwGsNOn: 0x0F, cwGsP: 0x2B),
];

const liteTypeARfProfiles = <TypeARfProfile>[
  TypeARfProfile(rfCfg: 0x29, cwGsNOn: 0x03, cwGsP: 0x11), // 档位 1
  TypeARfProfile(rfCfg: 0x49, cwGsNOn: 0x0B, cwGsP: 0x0C), // 档位 2
  pn532DefaultTypeARfProfile, // 档位 3
];

List<TypeARfProfile> typeARfProfilesForProductId(int productId) =>
    switch (productId) {
      0x0147 => standardTypeARfProfiles,
      0x0148 => liteTypeARfProfiles,
      _ => const [pn532DefaultTypeARfProfile],
    };

class UsbHinataDeviceImpl implements DeviceInterface {
  final HinataReader _hinata;
  final ValueNotifier<DeviceConnectionState> _connectionState = ValueNotifier(
    DeviceConnectionState.disconnected,
  );

  final StreamController<List<int>> _cardioStreamController =
      StreamController<List<int>>.broadcast();

  dynamic _activeTag;
  String? _pendingUnsupportedFingerprint;
  String? _confirmedUnsupportedFingerprint;

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

  @override
  bool get isRemote => false;

  @override
  String? get instanceId => null;

  @override
  String? get alias => null;

  @override
  String get displayTitle => productName;

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

  @override
  Future<void> resetLed() async {
    await _hinata.resetLed();
  }

  @override
  Future<ScannedCard?> poll({bool readExtended = true}) async {
    return (await pollResult(readExtended: readExtended)).card;
  }

  Future<CardReadResult> pollResult({bool readExtended = true}) async {
    try {
      final channel = HinataNfcCardChannel(_hinata.pn532Api);
      final engine = CardReaderEngine(channel);
      final felicaTag = await _pollFelicaTag();
      if (felicaTag != null) {
        _activeTag = felicaTag;
        return _resolvePollResult(
          await engine.processTag(
            felicaTag,
            source: 'HINATA',
            readExtended: readExtended,
          ),
        );
      }
      await _hinata.pn532Api.inRelease(1);

      final isoTag = await _pollIsoTag();
      if (isoTag != null) {
        _activeTag = isoTag;
        final result = await engine.processTag(
          isoTag,
          source: 'HINATA',
          readExtended: readExtended,
        );

        // Some phones expose their ISO14443A interface before FeliCa. Retry
        // FeliCa once before confirming that the Type A card is unsupported.
        if (result.status == CardReadStatus.confirmedUnsupported) {
          await _hinata.pn532Api.inRelease(1);

          final retryTag = await _pollFelicaTag();
          if (retryTag != null) {
            _activeTag = retryTag;
            return _resolvePollResult(
              await engine.processTag(
                retryTag,
                source: 'HINATA',
                readExtended: readExtended,
              ),
            );
          }
        }

        return _resolvePollResult(result);
      }

      _activeTag = null;
      return _resolvePollResult(const CardReadResult.noTarget());
    } catch (error, stackTrace) {
      debugPrint('USB NFC poll incomplete: $error\n$stackTrace');
      _activeTag = null;
      return _resolvePollResult(const CardReadResult.incomplete());
    }
  }

  CardReadResult _resolvePollResult(CardReadResult result) {
    if (result.status != CardReadStatus.confirmedUnsupported) {
      _pendingUnsupportedFingerprint = null;
      _confirmedUnsupportedFingerprint = null;
      return result;
    }

    final card = result.card?.card;
    if (card is! Iso14443) {
      _pendingUnsupportedFingerprint = null;
      _confirmedUnsupportedFingerprint = null;
      return result;
    }

    final fingerprint = '${card.idString}:${card.sak}:${card.atqa}';
    if (_confirmedUnsupportedFingerprint != fingerprint) {
      _confirmedUnsupportedFingerprint = null;
    }
    if (_confirmedUnsupportedFingerprint == fingerprint) {
      return result;
    }
    if (_pendingUnsupportedFingerprint == fingerprint) {
      _pendingUnsupportedFingerprint = null;
      _confirmedUnsupportedFingerprint = fingerprint;
      return result;
    }

    _pendingUnsupportedFingerprint = fingerprint;
    return const CardReadResult.incomplete();
  }

  @override
  Future<ScannedCard?> readExtended(ScannedCard basicCard) async {
    final tag = _activeTag;
    if (tag == null) {
      return null;
    }

    final channel = HinataNfcCardChannel(_hinata.pn532Api);
    final engine = CardReaderEngine(channel);

    final result = await engine.processTag(
      tag,
      source: 'HINATA',
      readExtended: true,
      existingCard: basicCard,
    );
    return result.status == CardReadStatus.recognized ? result.card : null;
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

  // ignore: unused_element
  Future<Iso14443?> _pollIsoTag() async {
    final profiles = typeARfProfilesForProductId(_hinata.pid);
    for (var i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      try {
        await _hinata.pn532Api.setTypeARfPower(
          rfCfg: profile.rfCfg,
          cwGsNOn: profile.cwGsNOn,
          cwGsP: profile.cwGsP,
        );
        final targets = await _hinata.pn532Api.inListPassiveTarget(0, 1, []);
        if (targets.isNotEmpty) {
          final t = targets[0];
          return Iso14443(t.id, t.sak!, t.atqa!);
        }
      } on TimeoutException catch (error) {
        throw TimeoutException(
          'Type A profile ${i + 1} '
          '(rfCfg=0x${profile.rfCfg.toRadixString(16).toUpperCase()}, '
          'cwGsNOn=0x${profile.cwGsNOn.toRadixString(16).toUpperCase()}, '
          'cwGsP=0x${profile.cwGsP.toRadixString(16).toUpperCase()}): '
          '${error.message}',
          error.duration,
        );
      }
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
