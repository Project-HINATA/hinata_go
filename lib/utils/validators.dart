import '../models/remote_instance.dart';

class Validators {
  static String buildValidUrl(String url, InstanceType type) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('://')) return trimmed;

    switch (type) {
      case InstanceType.hinataIo:
        return 'http://$trimmed';
      case InstanceType.spiceApiWebSocket:
        return 'ws://$trimmed';
      case InstanceType.spiceApi:
        return 'tcp://$trimmed';
    }
  }

  static bool isValidInstanceUrl(String url, InstanceType type) {
    final normalized = buildValidUrl(url, type);
    if (normalized.isEmpty) return false;

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return false;

    final scheme = uri.scheme.toLowerCase();
    switch (type) {
      case InstanceType.hinataIo:
        return scheme == 'http' || scheme == 'https';
      case InstanceType.spiceApi:
        return scheme == 'tcp' && uri.hasPort && uri.port > 0;
      case InstanceType.spiceApiWebSocket:
        final validWsSchemes = {'ws', 'wss', 'http', 'https'};
        return validWsSchemes.contains(scheme);
    }
  }
}
