import '../models/remote_instance.dart';
import '../services/spiceapi/spiceapi.dart';

class Validators {
  static String buildValidUrl(String url, InstanceType type) {
    var normalized = url.trim();
    if (normalized.isEmpty) return '';

    if (!normalized.contains('://')) {
      switch (type) {
        case InstanceType.hinataIo:
          return 'http://$normalized';
        case InstanceType.spiceApiWebSocket:
          return 'ws://$normalized';
        case InstanceType.spiceApi:
          return 'tcp://$normalized';
      }
    }
    return normalized;
  }

  static bool _hasValidSchemeForType(String scheme, InstanceType type) {
    switch (type) {
      case InstanceType.hinataIo:
        return scheme == 'http' || scheme == 'https';
      case InstanceType.spiceApi:
        return scheme == 'tcp';
      case InstanceType.spiceApiWebSocket:
        return scheme == 'ws' || scheme == 'wss' || scheme == 'http' || scheme == 'https';
    }
  }

  static bool isValidInstanceUrl(String url, InstanceType type) {
    var normalized = url.trim();
    if (normalized.isEmpty) return false;

    if (normalized.contains('://')) {
      final uri = Uri.tryParse(normalized);
      if (uri == null) return false;
      
      final scheme = uri.scheme.toLowerCase();
      if (!_hasValidSchemeForType(scheme, type)) {
        return false;
      }
    }

    final validUrl = buildValidUrl(normalized, type);
    if (validUrl.isEmpty) return false;

    if (type == InstanceType.hinataIo) {
      final uri = Uri.tryParse(validUrl);
      return uri != null && uri.host.isNotEmpty;
    } else {
      try {
        SpiceApiEndpoint.parse(validUrl);
        return true;
      } on FormatException {
        return false;
      }
    }
  }
}