import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/remote_instance.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

class ApiService {
  Future<bool> sendCardData({
    required RemoteInstance instance,
    required String type,
    required String value,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(instance.url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': type, 'value': value}),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
}
