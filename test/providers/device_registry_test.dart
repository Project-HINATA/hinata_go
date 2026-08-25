import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/models/card/card_read_result.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/models/remote_instance.dart';
import 'package:hinata_go/providers/current_scan_session_provider.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/services/communication/remote_hinata_impl.dart';

class FakeDeviceImpl implements DeviceInterface {
  @override
  final String deviceId;

  @override
  final String productName;

  @override
  final bool isRemote;

  @override
  String? alias;

  @override
  final ValueNotifier<DeviceConnectionState> connectionState =
      ValueNotifier(DeviceConnectionState.connected);

  final StreamController<List<int>> _cardioController =
      StreamController<List<int>>.broadcast();

  bool isDisconnected = false;
  bool isDisposed = false;

  FakeDeviceImpl({
    required this.deviceId,
    required this.productName,
    this.isRemote = false,
    this.alias,
  });

  @override
  String? get instanceId => isRemote ? deviceId : null;

  @override
  String get displayTitle => alias ?? productName;

  @override
  Stream<List<int>> get cardioInputStream => _cardioController.stream;

  @override
  Future<void> connect() async {
    connectionState.value = DeviceConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    isDisconnected = true;
    connectionState.value = DeviceConnectionState.disconnected;
  }

  @override
  void dispose() {
    isDisposed = true;
    _cardioController.close();
  }

  @override
  Future<void> enterBootloader() async {}

  @override
  Future<int> getConfig(int index) async => 0;

  @override
  Future<List<int>> getChipId() async => [0x01, 0x02];

  @override
  Future<int> getFirmTimeStamp() async => 12345678;

  @override
  Future<ScannedCard?> poll({bool readExtended = true}) async => null;

  @override
  Future<ScannedCard?> readExtended(ScannedCard basicCard) async => null;

  @override
  Future<void> resetLed() async {}

  @override
  Future<List<int>> sendCommand(
    int command,
    List<int> payload, {
    int timeoutMs = 1000,
  }) async => [];

  @override
  Future<void> setConfig(int index, int value) async {}

  @override
  Future<void> setLed(Color color) async {}
}

Felica _dummyFelica(String id) {
  return Felica(
    Uint8List.fromList(id.codeUnits),
    Uint8List(8),
    Uint16List.fromList([0x0001]),
  );
}

void main() {
  group('DeviceRegistryState', () {
    test('initial state has empty devices and null active device', () {
      final state = HardwareDeviceState();
      expect(state.devices, isEmpty);
      expect(state.activeDeviceId, isNull);
      expect(state.activeDevice, isNull);
      expect(state.connectedDevice, isNull);
      expect(state.hidAvailable, isFalse);
      expect(state.isConnecting, isFalse);
    });

    test('backward-compatible connectedDevice in constructor and copyWith', () {
      final fakeDev = FakeDeviceImpl(
        deviceId: 'usb_1',
        productName: 'HINATA Reader',
      );

      final stateWithDev = HardwareDeviceState(connectedDevice: fakeDev);
      expect(stateWithDev.devices.length, 1);
      expect(stateWithDev.devices['usb_1'], fakeDev);
      expect(stateWithDev.activeDeviceId, 'usb_1');
      expect(stateWithDev.activeDevice, fakeDev);
      expect(stateWithDev.connectedDevice, fakeDev);

      final clearedState = stateWithDev.copyWith(clearDevice: true);
      expect(clearedState.devices, isEmpty);
      expect(clearedState.activeDeviceId, isNull);
      expect(clearedState.activeDevice, isNull);
      expect(clearedState.connectedDevice, isNull);
    });
  });

  group('DeviceRegistryNotifier', () {
    test('registers multiple devices and selects active device', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev1 = FakeDeviceImpl(deviceId: 'usb_1', productName: 'Reader 1');
      final dev2 = FakeDeviceImpl(deviceId: 'usb_2', productName: 'Reader 2');

      notifier.registerDevice(dev1);
      var state = container.read(deviceRegistryProvider);
      expect(state.devices.length, 1);
      expect(state.activeDeviceId, 'usb_1');
      expect(state.activeDevice, dev1);

      notifier.registerDevice(dev2);
      state = container.read(deviceRegistryProvider);
      expect(state.devices.length, 2);
      expect(state.activeDeviceId, 'usb_1'); // Keeps first active by default

      // Switch active device
      notifier.selectDevice('usb_2');
      state = container.read(deviceRegistryProvider);
      expect(state.activeDeviceId, 'usb_2');
      expect(state.activeDevice, dev2);
    });

    test('sets and removes device alias', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev = FakeDeviceImpl(deviceId: 'usb_1', productName: 'HINATA Std');
      notifier.registerDevice(dev);

      notifier.setDeviceAlias('usb_1', 'Main Counter');
      var state = container.read(deviceRegistryProvider);
      expect(state.deviceAliases['usb_1'], 'Main Counter');
      expect(dev.displayTitle, 'Main Counter');

      // Clear alias
      notifier.setDeviceAlias('usb_1', '');
      state = container.read(deviceRegistryProvider);
      expect(state.deviceAliases.containsKey('usb_1'), isFalse);
      expect(dev.displayTitle, 'HINATA Std');
    });

    test('registers and unregisters remote devices', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final instance = RemoteInstance(
        id: 'inst_1',
        name: 'Arcade Cab 1',
        icon: 'gamepad',
        url: 'ws://127.0.0.1:8080',
      );
      final remoteDev = RemoteHinataDeviceImpl(instance: instance);

      notifier.registerRemoteDevice(remoteDev);
      var state = container.read(deviceRegistryProvider);
      expect(state.devices.containsKey('remote_inst_1'), isTrue);
      expect(state.activeDeviceId, 'remote_inst_1');
      expect(state.activeDevice, remoteDev);

      notifier.unregisterRemoteDevice('remote_inst_1');
      state = container.read(deviceRegistryProvider);
      expect(state.devices.containsKey('remote_inst_1'), isFalse);
      expect(state.activeDeviceId, isNull);
    });

    test('disconnecting active device falls back to remaining device', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev1 = FakeDeviceImpl(deviceId: 'usb_1', productName: 'Reader 1');
      final dev2 = FakeDeviceImpl(deviceId: 'usb_2', productName: 'Reader 2');

      notifier.registerDevice(dev1);
      notifier.registerDevice(dev2);

      notifier.selectDevice('usb_1');
      notifier.disconnect('usb_1');

      final state = container.read(deviceRegistryProvider);
      expect(state.devices.length, 1);
      expect(state.devices.containsKey('usb_1'), isFalse);
      expect(state.devices.containsKey('usb_2'), isTrue);
      expect(state.activeDeviceId, 'usb_2');
      expect(state.activeDevice, dev2);
      expect(dev1.isDisconnected, isTrue);
    });

    test('disconnectAll disconnects and clears all registered devices', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev1 = FakeDeviceImpl(deviceId: 'usb_1', productName: 'Reader 1');
      final dev2 = FakeDeviceImpl(deviceId: 'usb_2', productName: 'Reader 2');

      notifier.registerDevice(dev1);
      notifier.registerDevice(dev2);
      expect(container.read(deviceRegistryProvider).devices.length, 2);

      notifier.disconnectAll();
      final state = container.read(deviceRegistryProvider);
      expect(state.devices, isEmpty);
      expect(state.activeDeviceId, isNull);
      expect(state.activeDevice, isNull);
      expect(dev1.isDisconnected, isTrue);
      expect(dev2.isDisconnected, isTrue);
    });

    test('selecting invalid device does nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev1 = FakeDeviceImpl(deviceId: 'usb_1', productName: 'Reader 1');
      notifier.registerDevice(dev1);

      notifier.selectDevice('non_existent');
      expect(container.read(deviceRegistryProvider).activeDeviceId, 'usb_1');
    });

    test('auto-removes device when its connectionState turns disconnected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deviceRegistryProvider.notifier);
      final dev1 = FakeDeviceImpl(deviceId: 'usb_1', productName: 'Reader 1');
      final dev2 = FakeDeviceImpl(deviceId: 'usb_2', productName: 'Reader 2');
      notifier.registerDevice(dev1);
      notifier.registerDevice(dev2);

      dev1.connectionState.value = DeviceConnectionState.disconnected;

      final state = container.read(deviceRegistryProvider);
      expect(state.devices.containsKey('usb_1'), isFalse);
      expect(state.devices.containsKey('usb_2'), isTrue);
      expect(state.activeDeviceId, 'usb_2');
    });

    test('isolates card scan sessions and removal across multiple sources', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final scanNotifier = container.read(currentScanSessionProvider.notifier);
      final card1 = ScannedCard(
        card: _dummyFelica('CARD_DEV_1'),
        source: 'Reader 1',
      );

      // Record card from Reader 1
      scanNotifier.markCardPlaced(
        card1,
        presenceMode: ScanPresenceMode.explicitRemoval,
      );
      expect(container.read(currentScanSessionProvider).isCardPresent, isTrue);
      expect(container.read(currentScanSessionProvider).scannedCard?.source, 'Reader 1');

      // Reader 2 reports missing/noTarget -> should NOT affect Reader 1's present card
      final removedByOther = scanNotifier.markCardMissing(source: 'Reader 2');
      expect(removedByOther, isFalse);
      expect(container.read(currentScanSessionProvider).isCardPresent, isTrue);

      // Reader 1 reports missing 3 times -> card is removed
      expect(scanNotifier.markCardMissing(source: 'Reader 1'), isFalse);
      expect(scanNotifier.markCardMissing(source: 'Reader 1'), isFalse);
      expect(scanNotifier.markCardMissing(source: 'Reader 1'), isTrue);
      expect(container.read(currentScanSessionProvider).isCardPresent, isFalse);
    });
  });
}
