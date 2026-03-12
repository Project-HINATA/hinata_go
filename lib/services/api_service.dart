import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/iso15693.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/remote_instance.dart';
import 'spiceapi/spiceapi.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

class ApiServiceResult {
  final bool success;
  final String? errorMessage;

  ApiServiceResult({required this.success, this.errorMessage});
}

class ApiService {
  Future<ApiServiceResult> sendCardData({
    required RemoteInstance instance,
    required ICCard card,
  }) async {
    try {
      final validationError = _validateCard(card);
      if (validationError != null) {
        return validationError;
      }

      return _isSpiceApiInstance(instance)
          ? _sendSpiceApiCardData(instance: instance, card: card)
          : _sendHttpCardData(instance: instance, card: card);
    } on TimeoutException catch (_) {
      return _handleTimeout(instance);
    } on FormatException catch (e) {
      return ApiServiceResult(success: false, errorMessage: e.message);
    } on SocketException catch (e) {
      return _handleSocketError(instance, e);
    } catch (e, stackTrace) {
      return _handleUnknownError(e, stackTrace);
    }
  }

  bool _isSpiceApiInstance(RemoteInstance instance) {
    return instance.type == InstanceType.spiceApiUnit0 ||
        instance.type == InstanceType.spiceApiUnit1;
  }

  ApiServiceResult? _validateCard(ICCard card) {
    if (card.value != null && card.value!.isNotEmpty) {
      return null;
    }

    log('Card value is empty.');
    return ApiServiceResult(
      success: false,
      errorMessage: 'Card value is empty',
    );
  }

  Future<ApiServiceResult> _sendHttpCardData({
    required RemoteInstance instance,
    required ICCard card,
  }) async {
    if (card is Iso15693) {
      return ApiServiceResult(
        success: false,
        errorMessage: 'HTTP instances do not accept ISO15693 cards',
      );
    }

    final payload = {'type': card.type, 'value': card.value};
    log('Sending payload to ${instance.url}: ${jsonEncode(payload)}');

    final uri = Uri.parse(instance.url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();

      log('Response status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiServiceResult(success: true);
      }

      return ApiServiceResult(
        success: false,
        errorMessage: 'Server returned ${response.statusCode}',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ApiServiceResult> _sendSpiceApiCardData({
    required RemoteInstance instance,
    required ICCard card,
  }) async {
    final cardId = _resolveSpiceApiCardId(card);
    if (cardId == null) {
      log('Card type ${card.runtimeType} is not supported by SpiceAPI.');
      return ApiServiceResult(
        success: false,
        errorMessage: 'SpiceAPI only supports Felica and ISO15693 cards',
      );
    }

    final unit = instance.type == InstanceType.spiceApiUnit0 ? 0 : 1;
    final endpoint = SpiceApiEndpoint.parse(instance.url);
    log(
      'Sending SpiceAPI card insert to ${endpoint.host}:${endpoint.port} '
      'for unit $unit: ${card.idString}',
    );

    final connection = Connection(
      endpoint.host,
      endpoint.port,
      endpoint.pass,
      refreshSession: false,
    );

    try {
      await connection.onConnect().timeout(const Duration(seconds: 10));
      await cardInsert(
        connection,
        unit,
        cardId,
      ).timeout(const Duration(seconds: 10));
      return ApiServiceResult(success: true);
    } finally {
      connection.dispose();
    }
  }

  String? _resolveSpiceApiCardId(ICCard card) {
    if (card is Felica) {
      return card.idString;
    }

    if (card is Iso15693) {
      final uid = card.idString.toUpperCase();
      if (!uid.startsWith('E004')) {
        throw const FormatException(
          'ISO15693 card UID must start with E004 for SpiceAPI',
        );
      }
      return uid;
    }

    return null;
  }

  ApiServiceResult _handleTimeout(RemoteInstance instance) {
    log('Request to ${instance.url} timed out.');
    return ApiServiceResult(success: false, errorMessage: 'Request timed out');
  }

  ApiServiceResult _handleSocketError(
    RemoteInstance instance,
    SocketException error,
  ) {
    log('Network error connecting to ${instance.url}: $error');
    return ApiServiceResult(
      success: false,
      errorMessage: 'Network error: ${error.message}',
    );
  }

  ApiServiceResult _handleUnknownError(Object error, StackTrace stackTrace) {
    log('Unknown error in sendCardData: $error\n$stackTrace');
    return ApiServiceResult(
      success: false,
      errorMessage: 'Unknown error occurred',
    );
  }
}
