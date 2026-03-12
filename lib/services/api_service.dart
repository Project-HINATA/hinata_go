import 'dart:convert';
import 'dart:developer';
import 'dart:async';
import 'dart:io';
import 'package:hinata_go/models/card/card.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:http/http.dart' as http;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/remote_instance.dart';

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
      Map<String, dynamic> payload;

      if (card.value == null || card.value!.isEmpty) {
         log('Card value is empty.');
         return ApiServiceResult(success: false, errorMessage: 'Card value is empty');
      }

      if (instance.type == InstanceType.spiceApiUnit0 ||
          instance.type == InstanceType.spiceApiUnit1) {
        if (card is! Felica) {
          log('Card is not Felica, skipping SpiceAPI request.');
          return ApiServiceResult(success: false, errorMessage: 'SpiceAPI only supports Felica cards');
        }
        int unit = instance.type == InstanceType.spiceApiUnit0 ? 0 : 1;
        payload = {
          'id': 1,
          'module': 'card',
          'function': 'insert',
          'params': [
            unit,
            card.idString,
          ]
        };
      } else {
        payload = {'type': card.type, 'value': card.value};
      }

      log('Sending payload to ${instance.url}: ${jsonEncode(payload)}');

      final uri = Uri.parse(instance.url);
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      log('Response status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiServiceResult(success: true);
      } else {
        return ApiServiceResult(success: false, errorMessage: 'Server returned ${response.statusCode}');
      }
    } on TimeoutException catch (_) {
      log('Request to ${instance.url} timed out.');
      return ApiServiceResult(success: false, errorMessage: 'Request timed out');
    } on SocketException catch (e) {
      log('Network error connecting to ${instance.url}: $e');
      return ApiServiceResult(success: false, errorMessage: 'Network error: ${e.message}');
    } catch (e, stackTrace) {
      log('Unknown error in sendCardData: $e\n$stackTrace');
      return ApiServiceResult(success: false, errorMessage: 'Unknown error occurred');
    }
  }
}
