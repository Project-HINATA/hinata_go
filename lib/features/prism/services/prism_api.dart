import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:hinata_go/features/prism/services/prism_http_client.dart'
    if (dart.library.html) 'package:hinata_go/features/prism/services/prism_http_client_web.dart';
import 'package:hinata_go/features/prism/services/prism_location.dart';

Uri prismOrigin(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw ArgumentError('Invalid PRiSM origin');
  }
  return Uri.parse(uri.origin);
}

class PrismMachine {
  const PrismMachine({
    required this.publicId,
    required this.name,
    required this.shopName,
    this.heroUrl,
    this.machineGeo = true,
    this.billingEnabled = false,
    this.webOnly = false,
    this.capabilities,
    this.coinAfterSwipe = false,
  });

  final String publicId;
  final String name;
  final String shopName;
  final String? heroUrl;
  final bool machineGeo;
  final bool billingEnabled;
  final bool webOnly;
  final Map<String, bool>? capabilities;
  final bool coinAfterSwipe;
  bool get unified => capabilities != null;
  bool has(String capability) => capabilities == null
      ? capability == 'card'
      : capabilities![capability] == true;
  bool get empty => capabilities != null && !capabilities!.values.any((v) => v);

  factory PrismMachine.fromJson(Map<String, dynamic> json, {Uri? origin}) {
    final shop = json['shop'] as Map<String, dynamic>;
    return PrismMachine(
      publicId: json['publicId'] as String,
      name: json['name'] as String,
      shopName: shop['name'] as String,
      machineGeo:
          shop['locationEnabled'] as bool? ??
          shop['machineGeo'] as bool? ??
          true,
      billingEnabled: shop['billingEnabled'] as bool? ?? false,
      webOnly: json['webOnly'] as bool? ?? false,
      capabilities: (json['capabilities'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value == true),
      ),
      coinAfterSwipe: json['coinAfterSwipe'] == true,
      heroUrl: shop['heroUrl'] is String
          ? (origin ?? PrismAPI.defaultOrigin)
                .resolve(shop['heroUrl'] as String)
                .toString()
          : null,
    );
  }
}

class PrismMachineSession {
  const PrismMachineSession({
    required this.ticket,
    required this.expiresIn,
    required this.machine,
  });

  final String ticket;
  final int expiresIn;
  final PrismMachine machine;

  factory PrismMachineSession.fromJson(
    Map<String, dynamic> json, {
    Uri? origin,
  }) {
    return PrismMachineSession(
      ticket: json['ticket'] as String,
      expiresIn: json['expiresIn'] as int,
      machine: PrismMachine.fromJson(
        json['machine'] as Map<String, dynamic>,
        origin: origin,
      ),
    );
  }
}

class PrismCard {
  const PrismCard({
    required this.id,
    required this.label,
    required this.accessCode,
    required this.disabledAt,
  });

  final String id;
  final String label;
  final String accessCode;
  final String? disabledAt;

  factory PrismCard.fromJson(Map<String, dynamic> json) {
    return PrismCard(
      id: json['id'] as String,
      label: json['label'] as String,
      accessCode: json['accessCode'] as String,
      disabledAt: json['disabledAt'] as String?,
    );
  }
}

class PrismAPI {
  PrismAPI({http.Client? client, Uri? origin})
    : _client = client ?? createPrismHttpClient(),
      _baseURL = origin == null
          ? defaultOrigin
          : prismOrigin(origin.toString());

  final Uri _baseURL;
  Uri get origin => _baseURL;

  static final Uri defaultOrigin = Uri.parse(
    const String.fromEnvironment(
      'PRISM_API_ORIGIN',
      defaultValue: 'https://link.neri.moe',
    ),
  );
  final http.Client _client;

  Future<PrismMachineSession> startMachineSession({
    required String shopCode,
    required String publicId,
  }) async {
    final response = await _client.post(
      _baseURL.resolve('/api/v1/machines/session/start'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'shopCode': shopCode, 'publicId': publicId}),
    );
    final payload = _decode(response);
    return PrismMachineSession.fromJson(payload, origin: _baseURL);
  }

  Future<List<PrismCard>> cards() async {
    final response = await _client.get(_baseURL.resolve('/api/v1/cards'));
    final payload = _decode(response);
    final cards = payload['cards'] as List<dynamic>? ?? const [];
    return cards
        .map(
          (value) => PrismCard.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        )
        .where((card) => card.disabledAt == null)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> loginMachine({
    required String cardId,
    required String ticket,
    bool requireLocation = true,
    void Function()? onSending,
  }) async {
    final location = requireLocation ? await currentPrismLocation() : null;
    onSending?.call();
    final response = await _client.post(
      _baseURL.resolve('/api/v1/machines/login'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'cardId': cardId,
        if (location != null) ...{
          'lat': location.latitude,
          'lng': location.longitude,
          'accuracy': location.accuracy,
        },
        'ticket': ticket,
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool requireLocation = false,
  }) async {
    if (!path.startsWith('/api/v1/') || path.contains('..')) {
      throw ArgumentError('Invalid API path');
    }
    final payload = body == null ? null : Map<String, dynamic>.from(body);
    if (requireLocation) {
      final location = await currentPrismLocation();
      payload!['location'] = {
        'lat': location.latitude,
        'lng': location.longitude,
        'accuracy': location.accuracy,
      };
    }
    final response = payload == null
        ? await _client.get(_baseURL.resolve(path))
        : await _client.post(
            _baseURL.resolve(path),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          );
    return _decode(response);
  }

  Uri munetLoginURL(String ticket) {
    return _baseURL.replace(
      path: '/api/v1/auth/munet',
      queryParameters: {'next': '/m?ticket=${Uri.encodeComponent(ticket)}'},
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
      throw PrismException(
        (payload['error'] as Map<String, dynamic>?)?['message'] as String? ??
            'PRiSM 请求失败',
        code: (payload['error'] as Map<String, dynamic>?)?['code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return payload['data'] as Map<String, dynamic>;
  }
}

class PrismException implements Exception {
  const PrismException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
