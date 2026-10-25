import 'dart:typed_data';

/// Parses the hand-entered identity of a FeliCa card.
class FelicaInputValidator {
  static const maxSystemCodes = 16;

  static final _separators = RegExp(r'[\s:\-]');
  static final _hex = RegExp(r'^[0-9a-fA-F]+$');

  /// An 8-byte IDm or PMm written as 16 hex digits, spaces, colons and
  /// hyphens ignored; null when it is not one.
  static Uint8List? parseBytes8(String text) {
    final digits = text.replaceAll(_separators, '');
    if (digits.length != 16 || !_hex.hasMatch(digits)) return null;
    return Uint8List.fromList([
      for (var i = 0; i < 16; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ]);
  }

  /// System codes of 4 hex digits each, separated by commas or spaces; null
  /// unless there are 1 to [maxSystemCodes] distinct ones.
  static Uint16List? parseSystemCodes(String text) {
    final tokens = text
        .split(RegExp(r'[,，\s]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty || tokens.length > maxSystemCodes) return null;
    final codes = <int>[];
    for (final token in tokens) {
      if (token.length != 4 || !_hex.hasMatch(token)) return null;
      final code = int.parse(token, radix: 16);
      if (codes.contains(code)) return null;
      codes.add(code);
    }
    return Uint16List.fromList(codes);
  }
}
