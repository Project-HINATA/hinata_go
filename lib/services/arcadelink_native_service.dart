import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'arcadelink_api.dart';

class ArcadeLinkNativeService {
  static const _channel = MethodChannel('moe.neri.hinatago/arcadelink_native');

  static bool get isAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static bool get supportsNativePasskey => isAvailable;

  static bool get supportsNativeMunet => isAvailable;

  Future<void> authenticateWithPasskey() async {
    await _channel.invokeMethod<void>('authenticatePasskey');
  }

  Future<void> authenticateWithMunet() async {
    await _channel.invokeMethod<void>('authenticateMunet');
  }

  Future<List<ArcadeLinkCard>> loadCards() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('cards') ?? const [];
    return raw
        .map(
          (value) => ArcadeLinkCard.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool requireLocation = false,
  }) async {
    final raw = await _channel.invokeMethod<String>('request', {
      'path': path,
      if (body != null) 'body': jsonEncode(body),
      'requireLocation': requireLocation,
    });
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginMachine({
    required String cardId,
    required String ticket,
    bool requireLocation = true,
    VoidCallback? onSending,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'machineLoginSending') onSending?.call();
    });
    try {
      final raw = await _channel.invokeMethod<String>('loginMachine', {
        'cardId': cardId,
        'ticket': ticket,
        'requireLocation': requireLocation,
      });
      return raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
