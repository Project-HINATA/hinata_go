import 'dart:convert';

import 'package:http/http.dart' as http;

import 'arcadelink_http_client.dart'
    if (dart.library.html) 'arcadelink_http_client_web.dart';
import 'arcadelink_location.dart';

class ArcadeLinkMachine {
  const ArcadeLinkMachine({
    required this.publicId,
    required this.name,
    required this.shopName,
  });

  final String publicId;
  final String name;
  final String shopName;

  factory ArcadeLinkMachine.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>;
    return ArcadeLinkMachine(
      publicId: json['publicId'] as String,
      name: json['name'] as String,
      shopName: shop['name'] as String,
    );
  }
}

class ArcadeLinkMachineSession {
  const ArcadeLinkMachineSession({
    required this.ticket,
    required this.expiresIn,
    required this.machine,
  });

  final String ticket;
  final int expiresIn;
  final ArcadeLinkMachine machine;

  factory ArcadeLinkMachineSession.fromJson(Map<String, dynamic> json) {
    return ArcadeLinkMachineSession(
      ticket: json['ticket'] as String,
      expiresIn: json['expiresIn'] as int,
      machine: ArcadeLinkMachine.fromJson(
        json['machine'] as Map<String, dynamic>,
      ),
    );
  }
}

class ArcadeLinkCard {
  const ArcadeLinkCard({
    required this.id,
    required this.label,
    required this.accessCode,
    required this.disabledAt,
  });

  final String id;
  final String label;
  final String accessCode;
  final String? disabledAt;

  factory ArcadeLinkCard.fromJson(Map<String, dynamic> json) {
    return ArcadeLinkCard(
      id: json['id'] as String,
      label: json['label'] as String,
      accessCode: json['accessCode'] as String,
      disabledAt: json['disabledAt'] as String?,
    );
  }
}

class ArcadeLinkAPI {
  ArcadeLinkAPI({http.Client? client})
    : _client = client ?? createArcadeLinkHttpClient();

  static final Uri _baseURL = Uri.parse(
    const String.fromEnvironment(
      'ARCADELINK_API_ORIGIN',
      defaultValue: 'https://link.neri.moe',
    ),
  );
  final http.Client _client;

  Future<ArcadeLinkMachineSession> startMachineSession({
    required String shopCode,
    required String publicId,
  }) async {
    final response = await _client.post(
      _baseURL.resolve('/api/machines/session/start'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'shopCode': shopCode, 'publicId': publicId}),
    );
    final payload = _decode(response);
    return ArcadeLinkMachineSession.fromJson(payload);
  }

  Future<List<ArcadeLinkCard>> cards() async {
    final response = await _client.get(_baseURL.resolve('/api/cards'));
    final payload = _decode(response);
    final cards = payload['cards'] as List<dynamic>? ?? const [];
    return cards
        .map(
          (value) => ArcadeLinkCard.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        )
        .where((card) => card.disabledAt == null)
        .toList(growable: false);
  }

  Future<void> loginMachine({
    required String cardId,
    required String ticket,
  }) async {
    final location = await currentArcadeLinkLocation();
    final response = await _client.post(
      _baseURL.resolve('/api/machines/login'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'cardId': cardId,
        'lat': location.latitude,
        'lng': location.longitude,
        'accuracy': location.accuracy,
        'ticket': ticket,
      }),
    );
    _decode(response);
  }

  Uri munetLoginURL(String shopCode, String publicId) {
    return _baseURL.replace(
      path: '/api/auth/munet',
      queryParameters: {'next': '/arcadelink/$shopCode/$publicId'},
    );
  }

  Uri webFallbackURL(String ticket) {
    return _baseURL.replace(path: '/m', queryParameters: {'ticket': ticket});
  }

  void dispose() {
    _client.close();
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArcadeLinkException(
        payload['error'] as String? ?? 'ArcadeLink 请求失败',
        statusCode: response.statusCode,
      );
    }
    return payload;
  }
}

class ArcadeLinkException implements Exception {
  const ArcadeLinkException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
