import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/card/scanned_card.dart';
import '../../models/remote_instance.dart';
import '../remote_crypto.dart';
import 'device_interface.dart';

/// Standard JSON-RPC 2.0 error representation
class RpcException implements Exception {
  final int code;
  final String message;
  final dynamic data;

  const RpcException({required this.code, required this.message, this.data});

  factory RpcException.fromJson(Map<String, dynamic> json) {
    return RpcException(
      code: json['code'] as int? ?? -32603,
      message: json['message'] as String? ?? 'Internal RPC error',
      data: json['data'],
    );
  }

  @override
  String toString() => 'RpcException(code: $code, message: $message)';
}

/// Remote AimeIO device implementation communicating via WebSocket with E2EE JSON-RPC 2.0
class RemoteHinataDeviceImpl implements DeviceInterface {
  final RemoteInstance instance;
  final StreamChannel<dynamic> Function(Uri uri)? _channelFactory;

  final ValueNotifier<DeviceConnectionState> _connectionState =
      ValueNotifier(DeviceConnectionState.disconnected);

  final StreamController<List<int>> _cardioStreamController =
      StreamController<List<int>>.broadcast();

  final StreamController<Map<String, dynamic>> _firmwareProgressController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamChannel<dynamic>? _channel;
  StreamSubscription? _channelSub;
  int _rpcIdCounter = 0;
  final Map<String, Completer<dynamic>> _pendingRequests = {};
  bool _disposed = false;

  RemoteHinataDeviceImpl({
    required this.instance,
    StreamChannel<dynamic> Function(Uri uri)? channelFactory,
  }) : _channelFactory = channelFactory;

  /// Formats the remote instance URL into a proper WebSocket URI with role=controller
  static Uri buildWebSocketUri(String rawUrl) {
    var uri = Uri.parse(rawUrl);
    final scheme = switch (uri.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' => 'ws',
      'wss' => 'wss',
      _ => 'wss',
    };
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['role'] = 'controller';
    return uri.replace(scheme: scheme, queryParameters: queryParams);
  }

  @override
  String get deviceId => 'remote_${instance.id}';

  @override
  String get productName => instance.name.isNotEmpty
      ? 'Remote AimeIO (${instance.name})'
      : 'Remote AimeIO (${instance.id})';

  @override
  bool get isRemote => true;

  @override
  String? get instanceId => instance.id;

  @override
  String? get alias => instance.name.isNotEmpty ? instance.name : null;

  @override
  String get displayTitle => instance.name.isNotEmpty ? instance.name : productName;

  @override
  ValueNotifier<DeviceConnectionState> get connectionState => _connectionState;

  @override
  Stream<List<int>> get cardioInputStream => _cardioStreamController.stream;

  /// Stream of firmware progress events pushed from remote AimeIO
  Stream<Map<String, dynamic>> get firmwareProgressStream =>
      _firmwareProgressController.stream;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('RemoteHinataDeviceImpl has been disposed');
    }
    if (_connectionState.value == DeviceConnectionState.connected && _channel != null) {
      return;
    }

    _connectionState.value = DeviceConnectionState.connecting;
    try {
      final wsUri = buildWebSocketUri(instance.url);
      _channel = _channelFactory != null
          ? _channelFactory(wsUri)
          : WebSocketChannel.connect(wsUri);

      _channelSub = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleChannelError,
        onDone: _handleChannelDone,
        cancelOnError: true,
      );

      _connectionState.value = DeviceConnectionState.connected;
    } catch (e) {
      _connectionState.value = DeviceConnectionState.error;
      _cleanupConnection();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _cleanupConnection();
    _connectionState.value = DeviceConnectionState.disconnected;
  }

  void _cleanupConnection() {
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;

    // Fail any pending RPC requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('WebSocket disconnected'));
      }
    }
    _pendingRequests.clear();
  }

  void _handleChannelError(Object error) {
    debugPrint('[RemoteHinata] Channel error: $error');
    _connectionState.value = DeviceConnectionState.error;
    _cleanupConnection();
  }

  void _handleChannelDone() {
    debugPrint('[RemoteHinata] Channel closed');
    _connectionState.value = DeviceConnectionState.disconnected;
    _cleanupConnection();
  }

  Future<void> _handleIncomingMessage(dynamic raw) async {
    if (raw is! String) {
      return;
    }

    try {
      final dynamic decodedJson = jsonDecode(raw);
      if (decodedJson is! Map<String, dynamic>) {
        return;
      }

      Map<String, dynamic> payload;
      if (instance.password.isNotEmpty && decodedJson['action'] == 'E2EE_V1') {
        payload = await RemoteCrypto.decryptMessage(
          password: instance.password,
          envelope: decodedJson,
        );
      } else {
        payload = decodedJson;
      }

      _dispatchDecryptedMessage(payload);
    } catch (e, st) {
      debugPrint('[RemoteHinata] Failed to handle incoming message: $e\n$st');
    }
  }

  void _dispatchDecryptedMessage(Map<String, dynamic> message) {
    // 1. Check if this is a response to an active RPC request
    final id = message['id'];
    if (id != null) {
      final completer = _pendingRequests.remove(id.toString());
      if (completer != null && !completer.isCompleted) {
        if (message.containsKey('error') && message['error'] != null) {
          final errorMap = Map<String, dynamic>.from(message['error'] as Map);
          completer.completeError(RpcException.fromJson(errorMap));
        } else {
          completer.complete(message['result']);
        }
      }
      return;
    }

    // 2. Check if this is a notification/event
    final method = message['method'] as String?;
    if (method == 'event.firmwareProgress') {
      final params = message['params'];
      if (params is Map) {
        _firmwareProgressController.add(Map<String, dynamic>.from(params));
      }
    } else if (method == 'event.cardio') {
      final params = message['params'];
      if (params is List) {
        _cardioStreamController.add(params.cast<int>());
      }
    }
  }

  /// Sends an encrypted or plaintext JSON-RPC 2.0 request and awaits the result
  Future<dynamic> callRpc(
    String method, [
    dynamic params,
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    if (_disposed) {
      throw StateError('RemoteHinataDeviceImpl has been disposed');
    }
    if (_channel == null || _connectionState.value != DeviceConnectionState.connected) {
      await connect();
    }

    final reqId = 'req_${++_rpcIdCounter}_${const Uuid().v4().substring(0, 8)}';
    final rpcPayload = {
      'jsonrpc': '2.0',
      'id': reqId,
      'method': method,
      'params': params ?? <String, dynamic>{},
    };

    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;

    try {
      if (instance.password.isNotEmpty) {
        final salt = RemoteCrypto.decodeSalt(instance.encryptionSalt);
        final envelope = await RemoteCrypto.encryptMessage(
          password: instance.password,
          message: rpcPayload,
          salt: salt,
          messageId: const Uuid().v4(),
        );
        _channel!.sink.add(jsonEncode(envelope));
      } else {
        _channel!.sink.add(jsonEncode(rpcPayload));
      }

      return await completer.future.timeout(timeout);
    } catch (e) {
      _pendingRequests.remove(reqId);
      rethrow;
    }
  }

  @override
  Future<int> getFirmTimeStamp() async {
    final result = await callRpc('device.getInfo', {'unit': instance.unit});
    if (result is Map && result['firmware_timestamp'] != null) {
      return (result['firmware_timestamp'] as num).toInt();
    }
    return 0;
  }

  @override
  Future<List<int>> getChipId() async {
    final result = await callRpc('device.getInfo', {'unit': instance.unit});
    if (result is Map && result['chip_id'] != null) {
      final raw = result['chip_id'];
      if (raw is String) {
        return _parseHexBytes(raw);
      } else if (raw is List) {
        return raw.cast<int>();
      }
    }
    return [];
  }

  static List<int> _parseHexBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      if (i + 1 < clean.length) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return bytes;
  }

  @override
  Future<int> getConfig(int index) async {
    final result = await callRpc('device.getConfig', {'index': index});
    if (result is Map && result['value'] != null) {
      return (result['value'] as num).toInt();
    } else if (result is num) {
      return result.toInt();
    }
    return 0;
  }

  @override
  Future<void> setConfig(int index, int value) async {
    await callRpc('device.setConfig', {'index': index, 'value': value});
  }

  @override
  Future<void> setLed(Color color) async {
    await callRpc('device.setLed', {
      'r': (color.r * 255.0).round().clamp(0, 255),
      'g': (color.g * 255.0).round().clamp(0, 255),
      'b': (color.b * 255.0).round().clamp(0, 255),
      'unit': instance.unit,
    });
  }

  @override
  Future<void> resetLed() async {
    await callRpc('device.resetLed', {'unit': instance.unit});
  }

  /// Fetches AimeIO host process, version, active backends, and devices
  Future<Map<String, dynamic>> getIoInfo() async {
    final result = await callRpc('io.getInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Fetches [aimeio] INI configuration keys and values
  Future<Map<String, dynamic>> getIoConfig() async {
    final result = await callRpc('io.getConfig');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Updates a key-value pair in [aimeio] INI configuration
  Future<void> setIoConfig(String key, String value) async {
    await callRpc('io.setConfig', {'key': key, 'value': value});
  }

  /// Checks for available firmware updates
  Future<Map<String, dynamic>> checkFirmware({
    String channel = 'latest',
    String? version,
    bool? force,
    String? url,
  }) async {
    final params = <String, dynamic>{
      'channel': channel,
      if (version != null) 'version': version,
      if (force != null) 'force': force,
      if (url != null) 'url': url,
    };
    final result = await callRpc('firmware.check', params);
    return Map<String, dynamic>.from(result as Map);
  }

  /// Triggers self-contained remote firmware update on AimeIO
  Future<void> startFirmwareUpdate({
    String channel = 'latest',
    String? version,
    bool? force,
    String? url,
    String? firmwareHex,
    String? firmwareBase64,
  }) async {
    final params = <String, dynamic>{
      'channel': channel,
      if (version != null) 'version': version,
      if (force != null) 'force': force,
      if (url != null) 'url': url,
      if (firmwareHex != null) 'firmware_hex': firmwareHex,
      if (firmwareBase64 != null) 'firmware_base64': firmwareBase64,
    };
    await callRpc('firmware.start', params);
  }

  @override
  Future<void> enterBootloader() async {
    await callRpc('device.enterBootloader', {'unit': instance.unit});
  }

  @override
  Future<List<int>> sendCommand(
    int command,
    List<int> payload, {
    int timeoutMs = 1000,
  }) async {
    throw UnsupportedError('Raw sendCommand is not supported over remote RPC');
  }

  @override
  Future<ScannedCard?> poll({bool readExtended = true}) async => null;

  @override
  Future<ScannedCard?> readExtended(ScannedCard basicCard) async => null;

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _cardioStreamController.close();
    _firmwareProgressController.close();
  }
}
