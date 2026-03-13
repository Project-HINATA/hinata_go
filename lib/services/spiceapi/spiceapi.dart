import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
part "src/connection.dart";
part "src/request.dart";
part "src/response.dart";
part "src/exceptions.dart";
part "src/rc4.dart";
part "src/wrappers/analogs.dart";
part "src/wrappers/buttons.dart";
part "src/wrappers/capture.dart";
part "src/wrappers/card.dart";
part "src/wrappers/coin.dart";
part "src/wrappers/control.dart";
part "src/wrappers/info.dart";
part "src/wrappers/keypads.dart";
part "src/wrappers/lights.dart";
part "src/wrappers/memory.dart";
part "src/wrappers/iidx.dart";
part "src/wrappers/touch.dart";

class SpiceApiEndpoint {
  final String host;
  final int port;
  final String pass;

  const SpiceApiEndpoint({
    required this.host,
    required this.port,
    this.pass = '',
  });

  factory SpiceApiEndpoint.parse(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      throw const FormatException('SpiceAPI endpoint is empty.');
    }

    // Default to a dummy scheme if none is provided so Uri.tryParse can correctly parse host and port
    final hasScheme = normalized.contains('://');
    final uri = Uri.tryParse(hasScheme ? normalized : 'tcp://$normalized');
    
    if (uri == null) {
      throw FormatException('Invalid SpiceAPI endpoint: $raw');
    }

    if (uri.host.isEmpty) {
      throw FormatException('Missing SpiceAPI host: $raw');
    }

    if (uri.hasPort == false || uri.port <= 0) {
      throw FormatException('Missing SpiceAPI port: $raw');
    }

    var pass =
        uri.queryParameters['pass'] ?? uri.queryParameters['password'] ?? '';
    if (pass.isEmpty && uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      pass = parts.length > 1 ? parts.sublist(1).join(':') : parts.first;
    }

    return SpiceApiEndpoint(host: uri.host, port: uri.port, pass: pass);
  }
}
