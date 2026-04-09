import 'dart:typed_data';

/// Utility class for Hex-Byte conversions and formatting
class HexUtils {
  /// Converts a hex string to a Uint8List of bytes.
  /// If [input] is not valid hex (e.g., has length % 2 != 0 or non-hex chars),
  /// it treats it as a raw string and returns its code units.
  static Uint8List hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');

    // If length is odd or contains non-hex characters, treat as plain text
    if (cleanHex.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanHex)) {
      return Uint8List.fromList(cleanHex.codeUnits);
    }

    final length = cleanHex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Converts a list of bytes to a hex string.
  static String bytesToHex(List<int> bytes, {String separator = ''}) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(separator);
  }
}
