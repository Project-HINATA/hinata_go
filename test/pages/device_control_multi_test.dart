import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/scanned_card.dart';
import 'package:hinata_go/providers/current_scan_session_provider.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/ui/components/device/device_mini_bar.dart';
import 'package:hinata_go/ui/components/reader/current_scan_result_panel.dart';
import 'package:hinata_go/ui/pages/device_control_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<ProviderContainer> _createTestContainer({
  List<dynamic> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);

  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      storageProvider.overrideWithValue(storage),
      ...overrides.cast(),
    ],
  );
}

Widget _buildTestApp({
  required Widget home,
  required ProviderContainer container,
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

Felica _dummyFelica(String id) {
  return Felica(
    Uint8List.fromList(id.codeUnits),
    Uint8List(8),
    Uint16List.fromList([0x0001]),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeviceControlPage Multi-Device UI Tests', () {
    testWidgets('shows DisconnectedState when no devices connected', (
      tester,
    ) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(home: const DeviceControlPage(), container: container),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Device Connected'), findsOneWidget);
    });

    testWidgets(
      'renders single device dashboard without horizontal switcher bar',
      (tester) async {
        final container = await _createTestContainer();
        addTearDown(container.dispose);

        final notifier = container.read(hardwareDeviceProvider.notifier);
        final dev1 = FakeDeviceImpl(
          deviceId: 'usb_1',
          productName: 'HINATA Reader 1',
        );
        notifier.registerDevice(dev1);

        await tester.pumpWidget(
          _buildTestApp(
            home: const DeviceControlPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('HINATA Reader 1'), findsOneWidget);
        // Switcher bar is only shown when multiple devices exist
        expect(find.byType(ListView), findsOneWidget); // Only the dashboard list
      },
    );

    testWidgets(
      'renders top horizontal switcher bar and allows switching active device when multiple devices exist',
      (tester) async {
        final container = await _createTestContainer();
        addTearDown(container.dispose);

        final notifier = container.read(hardwareDeviceProvider.notifier);
        final dev1 = FakeDeviceImpl(
          deviceId: 'usb_1',
          productName: '1P Reader',
        );
        final dev2 = FakeDeviceImpl(
          deviceId: 'usb_2',
          productName: '2P Reader',
        );
        notifier.registerDevice(dev1);
        notifier.registerDevice(dev2);

        await tester.pumpWidget(
          _buildTestApp(
            home: const DeviceControlPage(),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Both devices are visible in switcher bar
        expect(find.text('1P Reader'), findsWidgets);
        expect(find.text('2P Reader'), findsWidgets);
        expect(
          container.read(hardwareDeviceProvider).activeDeviceId,
          'usb_1',
        );

        // Tap on 2P Reader in switcher bar to switch
        await tester.tap(find.text('2P Reader').first);
        await tester.pumpAndSettle();

        expect(
          container.read(hardwareDeviceProvider).activeDeviceId,
          'usb_2',
        );
      },
    );

    testWidgets('allows editing device alias via dialog', (tester) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(hardwareDeviceProvider.notifier);
      final dev1 = FakeDeviceImpl(
        deviceId: 'usb_1',
        productName: 'HINATA Std',
      );
      final dev2 = FakeDeviceImpl(
        deviceId: 'usb_2',
        productName: 'HINATA Lite',
      );
      notifier.registerDevice(dev1);
      notifier.registerDevice(dev2);

      await tester.pumpWidget(
        _buildTestApp(
          home: const DeviceControlPage(),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Find the edit alias icon button and tap it
      final editButtons = find.byIcon(Icons.edit_outlined);
      expect(editButtons, findsWidgets);
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Edit Device Alias'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter new alias
      await tester.enterText(find.byType(TextField), 'Main Counter Reader');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify alias is set in state and UI
      expect(
        container.read(hardwareDeviceProvider).deviceAliases['usb_1'],
        'Main Counter Reader',
      );
      expect(find.text('Main Counter Reader'), findsWidgets);
    });
  });

  group('DeviceMiniBar Multi-Device Tests', () {
    testWidgets('shows single device name when 1 device connected', (
      tester,
    ) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(hardwareDeviceProvider.notifier);
      final dev = FakeDeviceImpl(
        deviceId: 'usb_1',
        productName: 'HINATA Reader',
      );
      notifier.registerDevice(dev);

      await tester.pumpWidget(
        _buildTestApp(
          home: const Scaffold(body: DeviceMiniBar()),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HINATA Reader'), findsOneWidget);
    });

    testWidgets(
      'shows aggregated count and active device subtitle when multiple devices connected',
      (tester) async {
        final container = await _createTestContainer();
        addTearDown(container.dispose);

        final notifier = container.read(hardwareDeviceProvider.notifier);
        final dev1 = FakeDeviceImpl(
          deviceId: 'usb_1',
          productName: '1P Reader',
        );
        final dev2 = FakeDeviceImpl(
          deviceId: 'usb_2',
          productName: '2P Reader',
        );
        notifier.registerDevice(dev1);
        notifier.registerDevice(dev2);

        await tester.pumpWidget(
          _buildTestApp(
            home: const Scaffold(body: DeviceMiniBar()),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 Devices Connected'), findsOneWidget);
        expect(find.text('Active: 1P Reader'), findsOneWidget);
      },
    );

    testWidgets('tapping DeviceMiniBar opens bottom sheet with device switcher', (
      tester,
    ) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(hardwareDeviceProvider.notifier);
      final dev1 = FakeDeviceImpl(
        deviceId: 'usb_1',
        productName: '1P Reader',
      );
      final dev2 = FakeDeviceImpl(
        deviceId: 'usb_2',
        productName: '2P Reader',
      );
      notifier.registerDevice(dev1);
      notifier.registerDevice(dev2);

      await tester.pumpWidget(
        _buildTestApp(
          home: const Scaffold(body: DeviceMiniBar()),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Tap mini bar
      await tester.tap(find.byType(DeviceMiniBar));
      await tester.pumpAndSettle();

      // Bottom sheet appears with device switcher cards
      expect(find.text('1P Reader'), findsWidgets);
      expect(find.text('2P Reader'), findsWidgets);
    });
  });

  group('ScanPage Source Badge Tests', () {
    testWidgets('renders source device badge when card is scanned', (
      tester,
    ) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      final scanNotifier = container.read(currentScanSessionProvider.notifier);
      final card = ScannedCard(
        card: _dummyFelica('CARD_DEV_1P'),
        source: '1P Reader',
      );
      scanNotifier.markCardPlaced(card);

      await tester.pumpWidget(
        _buildTestApp(
          home: const Scaffold(body: CurrentScanResultPanel()),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('From: 1P Reader'), findsOneWidget);
      expect(find.byIcon(Icons.sensors_rounded), findsOneWidget);
    });

    testWidgets('renders source badge in Chinese locale as 来自: ...', (
      tester,
    ) async {
      final container = await _createTestContainer();
      addTearDown(container.dispose);

      final scanNotifier = container.read(currentScanSessionProvider.notifier);
      final card = ScannedCard(
        card: _dummyFelica('CARD_DEV_2P'),
        source: '2P 读卡器',
      );
      scanNotifier.markCardPlaced(card);

      await tester.pumpWidget(
        _buildTestApp(
          home: const Scaffold(body: CurrentScanResultPanel()),
          container: container,
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('来自: 2P 读卡器'), findsOneWidget);
    });
  });
}
