import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/saved_card.dart';
import 'package:hinata_go/models/remote_instance.dart';
import 'package:hinata_go/providers/app_state_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/services/communication/remote_hinata_impl.dart';
import 'package:hinata_go/services/notification_service.dart';
import 'package:hinata_go/ui/pages/remote/components/instance_selector_bar.dart';
import 'package:hinata_go/ui/pages/remote/components/io_config_card.dart';
import 'package:hinata_go/ui/pages/remote/components/quick_actions_card.dart';
import 'package:hinata_go/ui/pages/remote/components/remote_firmware_dialog.dart';
import 'package:hinata_go/ui/pages/remote/components/remote_reader_card.dart';
import 'package:hinata_go/ui/pages/remote/remote_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';

class FakeRemoteChannel {
  final StreamController<dynamic> _toClient =
      StreamController<dynamic>.broadcast(sync: true);
  final StreamController<dynamic> _fromClient =
      StreamController<dynamic>.broadcast(sync: true);

  FakeRemoteChannel() {
    _fromClient.stream.listen(_handleIncomingRpc);
  }

  StreamChannel<dynamic> get channel =>
      StreamChannel<dynamic>(_toClient.stream, _fromClient.sink);

  void _handleIncomingRpc(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final id = msg['id'];
      final method = msg['method'] as String?;

      if (id == null) return;

      dynamic result;
      if (method == 'io.getInfo') {
        result = {
          'version': '1.2.3',
          'process': 'hinata-aimeio-rs',
          'backends': ['hinata', 'remote'],
          'config_path': 'aimeio.ini',
        };
      } else if (method == 'io.getConfig') {
        result = {
          'logLevel': 'info',
          'brightness': '200',
          'tunion': 'true',
          'autoUpdate': 'false',
          'reportUrl': 'https://report.test',
        };
      } else if (method == 'io.setConfig') {
        result = {'success': true};
      } else if (method == 'device.getInfo') {
        result = {
          'firmware_timestamp': 1700000000,
          'chip_id': '0102030405060708',
          'pid': 0x0147,
        };
      } else if (method == 'device.getConfig') {
        result = {'value': 42};
      } else if (method == 'device.setConfig') {
        result = {'success': true};
      } else if (method == 'device.setLed' || method == 'device.resetLed') {
        result = {'status': 'ok'};
      } else if (method == 'game.insertCoin' || method == 'io.insertCoin') {
        result = {'success': true};
      } else if (method == 'game.buttonPress' || method == 'io.buttonPress') {
        result = {'success': true};
      } else if (method == 'firmware.check') {
        result = {
          'has_update': true,
          'latest_version': 'v2.5.0',
          'changelog': 'Bugfixes and stability improvements.',
        };
      } else if (method == 'firmware.start') {
        result = {'status': 'started'};
        Future.microtask(() {
          if (!_toClient.isClosed) {
            _toClient.add(jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event.firmwareProgress',
              'params': {
                'stage': 'flashing',
                'progress': 50,
                'message': 'Flashing flash block 2/4...',
              },
            }));
          }
        });
      } else {
        result = {};
      }

      if (!_toClient.isClosed) {
        _toClient.add(jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': result,
        }));
      }
    } catch (_) {}
  }

  void close() {
    _toClient.close();
    _fromClient.close();
  }
}

class MockNotificationService extends NotificationService {
  @override
  void showSuccess(String message) {}
  @override
  void showError(String message) {}
  @override
  void showInfo(String message) {}
}

Widget createRemoteTestApp({
  required SharedPreferences preferences,
  List<dynamic> overrides = const [],
}) {
  final storage = StorageService(preferences);

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      storageProvider.overrideWithValue(storage),
      notificationServiceProvider.overrideWithValue(MockNotificationService()),
      ...overrides.cast(),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RemotePage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late FakeRemoteChannel fakeChannel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    fakeChannel = FakeRemoteChannel();
  });

  tearDown(() {
    fakeChannel.close();
  });

  group('RemotePage & Subcomponents Tests', () {
    testWidgets('shows empty state when no instances are configured', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRemoteTestApp(preferences: preferences));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSelectorBar), findsOneWidget);
      expect(find.text('No instances configured. Add an instance to start remote management.'), findsNWidgets(2));
      expect(find.text('Add Instance'), findsOneWidget);
    });

    testWidgets('renders instance chips and allows switching active instance', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = StorageService(preferences);
      final inst1 = RemoteInstance(
        id: 'inst_1',
        name: 'Cabinet 1P',
        url: 'ws://127.0.0.1:8080',
        icon: 'gamepad',
        type: InstanceType.hinataIo,
      );
      final inst2 = RemoteInstance(
        id: 'inst_2',
        name: 'Cabinet 2P',
        url: 'ws://127.0.0.1:8081',
        icon: 'joystick',
        type: InstanceType.hinataIo,
      );

      await storage.saveInstances([inst1, inst2]);
      await storage.setActiveInstanceId('inst_1');

      final device1 = RemoteHinataDeviceImpl(
        instance: inst1,
        channelFactory: (_) => fakeChannel.channel,
      );

      await tester.pumpWidget(
        createRemoteTestApp(
          preferences: preferences,
          overrides: [
            activeRemoteDeviceProvider.overrideWithValue(device1),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // InstanceSelectorBar has both instances
      expect(find.text('Cabinet 1P'), findsOneWidget);
      expect(find.text('Cabinet 2P'), findsOneWidget);

      // Subcomponents rendered for active instance 1
      expect(find.byType(QuickActionsCard), findsOneWidget);
      expect(find.byType(IoConfigCard), findsOneWidget);
      expect(find.byType(RemoteReaderCard), findsOneWidget);

      // Tap Cabinet 2P to switch instance
      await tester.tap(find.text('Cabinet 2P'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Verification of active id change
      expect(storage.getActiveInstanceId(), 'inst_2');
    });

    testWidgets('QuickActionsCard renders saved cards and virtual control buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = StorageService(preferences);
      final inst = RemoteInstance(
        id: 'inst_1',
        name: 'Main Cabinet',
        url: 'ws://127.0.0.1:8080',
        icon: 'gamepad',
        type: InstanceType.hinataIo,
      );
      await storage.saveInstances([inst]);
      await storage.setActiveInstanceId('inst_1');

      // Add a saved card
      final savedCard = SavedCard(
        id: 'card_1',
        name: 'My Aime Pass',
        folderId: 'favorites_folder',
        card: Felica(
          Uint8List.fromList('0123456789'.codeUnits),
          Uint8List(8),
          Uint16List.fromList([0x0001]),
        ),
      );
      await storage.saveSavedCards([savedCard]);

      final device = RemoteHinataDeviceImpl(
        instance: inst,
        channelFactory: (_) => fakeChannel.channel,
      );

      await tester.pumpWidget(
        createRemoteTestApp(
          preferences: preferences,
          overrides: [
            activeRemoteDeviceProvider.overrideWithValue(device),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Check card chip is visible
      expect(find.text('My Aime Pass'), findsOneWidget);

      // Check coin buttons
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('+3'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);

      // Check Service & Test buttons
      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);

      // Tap coin button
      await tester.tap(find.text('+1'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Tap Service button
      await tester.tap(find.text('Service'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    });

    testWidgets('IoConfigCard and RemoteReaderCard load info and trigger update dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = StorageService(preferences);
      final inst = RemoteInstance(
        id: 'inst_1',
        name: 'Main Cabinet',
        url: 'ws://127.0.0.1:8080',
        icon: 'gamepad',
        type: InstanceType.hinataIo,
      );
      await storage.saveInstances([inst]);
      await storage.setActiveInstanceId('inst_1');

      final device = RemoteHinataDeviceImpl(
        instance: inst,
        channelFactory: (_) => fakeChannel.channel,
      );

      await tester.pumpWidget(
        createRemoteTestApp(
          preferences: preferences,
          overrides: [
            activeRemoteDeviceProvider.overrideWithValue(device),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // IoConfigCard content
      expect(find.text('IO Configuration'), findsOneWidget);
      expect(find.text('hinata-aimeio-rs (1.2.3)'), findsOneWidget);
      expect(find.text('Save IO Config'), findsOneWidget);

      // RemoteReaderCard content
      expect(find.text('Remote Reader'), findsOneWidget);
      expect(find.text('Rainbow Light'), findsOneWidget);
      expect(find.text('Rapid Scan'), findsOneWidget);

      // Open firmware update dialog
      final updateButton = find.widgetWithText(OutlinedButton, 'Firmware Update');
      expect(updateButton, findsOneWidget);
      await tester.tap(updateButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.byType(RemoteFirmwareDialog), findsOneWidget);
      expect(find.text('New Firmware Available: v2.5.0'), findsOneWidget);
      expect(find.text('Start Update'), findsOneWidget);

      // Start update
      await tester.tap(find.text('Start Update'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Updating firmware...'), findsOneWidget);
    });
  });
}
