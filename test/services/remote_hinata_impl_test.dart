import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/remote_instance.dart';
import 'package:hinata_go/services/communication/device_interface.dart';
import 'package:hinata_go/services/communication/remote_hinata_impl.dart';
import 'package:hinata_go/services/remote_crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:stream_channel/stream_channel.dart';

/// Helper to create a paired mock StreamChannel
class MockWebSocketPair {
  final StreamController<dynamic> _toClient = StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _fromClient = StreamController<dynamic>.broadcast();

  late final StreamChannel<dynamic> clientChannel;

  MockWebSocketPair() {
    clientChannel = StreamChannel<dynamic>(
      _toClient.stream,
      _fromClient.sink,
    );
  }

  Stream<dynamic> get incomingFromClient => _fromClient.stream;

  void sendToClient(dynamic message) {
    _toClient.add(message);
  }

  void close() {
    _toClient.close();
    _fromClient.close();
  }
}

void main() {
  group('RemoteHinataDeviceImpl URL & Metadata', () {
    test('buildWebSocketUri correctly formats url and adds role=controller', () {
      final uri1 = RemoteHinataDeviceImpl.buildWebSocketUri('https://aime-ws.neri.moe/ROOM1');
      expect(uri1.scheme, equals('wss'));
      expect(uri1.host, equals('aime-ws.neri.moe'));
      expect(uri1.path, equals('/ROOM1'));
      expect(uri1.queryParameters['role'], equals('controller'));

      final uri2 = RemoteHinataDeviceImpl.buildWebSocketUri('http://localhost:8080/ws?foo=bar');
      expect(uri2.scheme, equals('ws'));
      expect(uri2.host, equals('localhost'));
      expect(uri2.port, equals(8080));
      expect(uri2.queryParameters['foo'], equals('bar'));
      expect(uri2.queryParameters['role'], equals('controller'));
    });

    test('metadata properties match RemoteInstance and DeviceInterface specs', () {
      final instance = RemoteInstance(
        id: 'inst-123',
        name: 'Cabinet 1P',
        icon: 'gamepad',
        url: 'https://aime-ws.neri.moe/CAB1',
        password: 'secret-password',
      );

      final device = RemoteHinataDeviceImpl(instance: instance);

      expect(device.isRemote, isTrue);
      expect(device.instanceId, equals('inst-123'));
      expect(device.alias, equals('Cabinet 1P'));
      expect(device.displayTitle, equals('Cabinet 1P'));
      expect(device.deviceId, equals('remote_inst-123'));
      expect(device.productName, contains('Cabinet 1P'));
      expect(device.connectionState.value, equals(DeviceConnectionState.disconnected));
    });
  });

  group('RemoteHinataDeviceImpl E2EE RPC Communication', () {
    late RemoteInstance instance;
    late MockWebSocketPair mockWs;
    late RemoteHinataDeviceImpl device;
    late StreamSubscription fromClientSub;

    setUp(() {
      instance = RemoteInstance(
        id: 'test-inst',
        name: 'Test Device',
        icon: 'icon',
        url: 'wss://test.local/ws',
        password: 'password123',
      );
      mockWs = MockWebSocketPair();
      device = RemoteHinataDeviceImpl(
        instance: instance,
        channelFactory: (_) => mockWs.clientChannel,
      );
    });

    tearDown(() async {
      await fromClientSub.cancel();
      await device.disconnect();
      mockWs.close();
    });

    test('connect and disconnect updates connectionState', () async {
      fromClientSub = mockWs.incomingFromClient.listen((_) {});

      expect(device.connectionState.value, equals(DeviceConnectionState.disconnected));
      await device.connect();
      expect(device.connectionState.value, equals(DeviceConnectionState.connected));

      await device.disconnect();
      expect(device.connectionState.value, equals(DeviceConnectionState.disconnected));
    });

    test('performs E2EE encrypted RPC request and response matching (getFirmTimeStamp & getChipId)', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        expect(envelope['action'], equals('E2EE_V1'));

        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );

        expect(decrypted['jsonrpc'], equals('2.0'));
        expect(decrypted['method'], equals('device.getInfo'));

        final reqId = decrypted['id'];
        final responsePayload = {
          'jsonrpc': '2.0',
          'id': reqId,
          'result': {
            'connected': true,
            'firmware_timestamp': 1700001234,
            'commit_hash': 'abcdef12',
            'chip_id': '0102030405060708',
          },
        };

        final respEnvelope = await RemoteCrypto.encryptMessage(
          password: instance.password,
          message: responsePayload,
          salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
          messageId: const Uuid().v4(),
        );

        mockWs.sendToClient(jsonEncode(respEnvelope));
      });

      await device.connect();

      final timestamp = await device.getFirmTimeStamp();
      expect(timestamp, equals(1700001234));

      final chipId = await device.getChipId();
      expect(chipId, equals([1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test('getConfig and setConfig RPC methods', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );
        final reqId = decrypted['id'];
        final method = decrypted['method'];
        final params = decrypted['params'] as Map<String, dynamic>;

        if (method == 'device.getConfig') {
          expect(params['index'], equals(0));
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'index': 0, 'value': 42},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        } else if (method == 'device.setConfig') {
          expect(params['index'], equals(0));
          expect(params['value'], equals(100));
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'success': true, 'index': 0, 'value': 100},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        }
      });

      await device.connect();

      final val = await device.getConfig(0);
      expect(val, equals(42));

      await device.setConfig(0, 100);
    });

    test('setLed and resetLed RPC methods', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );
        final reqId = decrypted['id'];
        final method = decrypted['method'];
        final params = decrypted['params'] as Map<String, dynamic>;

        if (method == 'device.setLed') {
          expect(params['r'], equals(255));
          expect(params['g'], equals(128));
          expect(params['b'], equals(0));
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'status': 'ok'},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        } else if (method == 'device.resetLed') {
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'status': 'ok'},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        }
      });

      await device.connect();

      await device.setLed(const Color.fromARGB(255, 255, 128, 0));
      await device.resetLed();
    });

    test('getIoInfo, getIoConfig, setIoConfig RPC methods', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );
        final reqId = decrypted['id'];
        final method = decrypted['method'];
        final params = decrypted['params'] as Map<String, dynamic>;

        if (method == 'io.getInfo') {
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {
              'version': '1.2.3',
              'process': 'hinata-aimeio-rs',
              'backends': ['hinata', 'remote'],
              'config_path': 'aimeio.ini',
              'devices': [
                {'instance_id': 'inst-1', 'name': 'Reader 1', 'pid': 327}
              ],
            },
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        } else if (method == 'io.getConfig') {
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {
              'logLevel': 'info',
              'brightness': '8',
              'tunion': 'true',
            },
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        } else if (method == 'io.setConfig') {
          expect(params['key'], equals('logLevel'));
          expect(params['value'], equals('debug'));
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'success': true},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        }
      });

      await device.connect();

      final ioInfo = await device.getIoInfo();
      expect(ioInfo['version'], equals('1.2.3'));
      expect(ioInfo['process'], equals('hinata-aimeio-rs'));
      expect(ioInfo['backends'], equals(['hinata', 'remote']));

      final ioConfig = await device.getIoConfig();
      expect(ioConfig['logLevel'], equals('info'));
      expect(ioConfig['brightness'], equals('8'));

      await device.setIoConfig('logLevel', 'debug');
    });

    test('checkFirmware, startFirmwareUpdate and firmwareProgressStream event notifications', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );
        final reqId = decrypted['id'];
        final method = decrypted['method'];
        final params = decrypted['params'] as Map<String, dynamic>;

        if (method == 'firmware.check') {
          expect(params['channel'], equals('latest'));
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {
              'has_update': true,
              'is_latest': false,
              'latest_version': 'v2.4.0',
              'firmware_available': true,
            },
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));
        } else if (method == 'firmware.start') {
          // Send start response
          final respPayload = {
            'jsonrpc': '2.0',
            'id': reqId,
            'result': {'status': 'started'},
          };
          final respEnv = await RemoteCrypto.encryptMessage(
            password: instance.password,
            message: respPayload,
            salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
            messageId: const Uuid().v4(),
          );
          mockWs.sendToClient(jsonEncode(respEnv));

          // Send asynchronous progress events
          for (final (stage, progress, msg) in [
            ('downloading', 20, 'Downloading firmware...'),
            ('flashing', 60, 'Flashing flash block 3/5...'),
            ('complete', 100, 'Firmware update successful!'),
          ]) {
            final notificationPayload = {
              'jsonrpc': '2.0',
              'method': 'event.firmwareProgress',
              'params': {
                'stage': stage,
                'progress': progress,
                'message': msg,
              },
            };
            final notifEnv = await RemoteCrypto.encryptMessage(
              password: instance.password,
              message: notificationPayload,
              salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
              messageId: const Uuid().v4(),
            );
            mockWs.sendToClient(jsonEncode(notifEnv));
          }
        }
      });

      await device.connect();

      final checkResult = await device.checkFirmware(channel: 'latest');
      expect(checkResult['has_update'], isTrue);
      expect(checkResult['latest_version'], equals('v2.4.0'));

      final progressEvents = <Map<String, dynamic>>[];
      final progressSub = device.firmwareProgressStream.listen((event) {
        progressEvents.add(event);
      });

      await device.startFirmwareUpdate(channel: 'latest');

      // Wait briefly for progress events to arrive
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(progressEvents.length, equals(3));
      expect(progressEvents[0]['stage'], equals('downloading'));
      expect(progressEvents[1]['progress'], equals(60));
      expect(progressEvents[2]['stage'], equals('complete'));

      await progressSub.cancel();
    });

    test('RPC error response throws RpcException', () async {
      fromClientSub = mockWs.incomingFromClient.listen((rawMessage) async {
        final envelope = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        final decrypted = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: envelope,
        );
        final reqId = decrypted['id'];
        final respPayload = {
          'jsonrpc': '2.0',
          'id': reqId,
          'error': {
            'code': -32601,
            'message': 'Method not found: invalidMethod',
          },
        };
        final respEnv = await RemoteCrypto.encryptMessage(
          password: instance.password,
          message: respPayload,
          salt: RemoteCrypto.decodeSalt(instance.encryptionSalt),
          messageId: const Uuid().v4(),
        );
        mockWs.sendToClient(jsonEncode(respEnv));
      });

      await device.connect();

      expect(
        () => device.callRpc('invalidMethod'),
        throwsA(isA<RpcException>().having((e) => e.code, 'code', equals(-32601))),
      );
    });
  });
}
