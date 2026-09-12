import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:hinata_go/features/prism/services/prism_api.dart';

class PrismNativeService {
  PrismNativeService({Uri? origin}) : origin = origin ?? PrismAPI.defaultOrigin;
  final Uri origin;
  static const _channel = MethodChannel('moe.neri.hinatago/prism_native');

  static bool get isAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static bool get supportsNativePasskey => isAvailable;

  static bool get supportsNativeMunet => isAvailable;

  Future<void> authenticateWithPasskey() async {
    await _channel.invokeMethod<void>('authenticatePasskey', {
      'origin': origin.toString(),
    });
  }

  Future<void> authenticateWithMunet() async {
    await _channel.invokeMethod<void>('authenticateMunet', {
      'origin': origin.toString(),
    });
  }

  Future<List<PrismCard>> loadCards() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>('cards', {
          'origin': origin.toString(),
        }) ??
        const [];
    return raw
        .map(
          (value) => PrismCard.fromJson(
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
      'origin': origin.toString(),
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
        'origin': origin.toString(),
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
