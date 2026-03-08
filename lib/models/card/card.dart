import 'dart:typed_data';

import 'aic.dart';
import 'aime.dart';
import 'banapass.dart';
import 'felica.dart';
import 'iso14443a.dart';

class ICCard {
  final Uint8List id;
  ICCard(this.id);
  String get idString =>
      id.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  String get name => "Generic IC Card";

  String? get type => null;

  String? get value => null;

  Map<String, dynamic> toJson() {
    return {'type': type, 'id': _bytesToHex(id)};
  }

  /// Dispatch deserialization to the correct subclass based on `type`.
  static ICCard fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'aic':
        return Aic.fromJson(json);
      case 'aime':
        return Aime.fromJson(json);
      case 'felica':
        return Felica.fromJson(json);
      case 'mifare':
        return Banapass.fromJson(json);
      case 'iso14443':
        return Iso14443.fromJson(json);
      default:
        return ICCard(hexToBytes(json['id'] as String? ?? ''));
    }
  }

  /// Reconstruct from flat type + value strings (e.g. from [ScanLog]).
  static ICCard fromTypeAndValue(String type, String value) {
    return fromJson({
      'type': type,
      'id': '',
      'accessCode': value,
      'block1': value,
    });
  }

  // --- Hex utilities ---

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    if (cleanHex.isEmpty) return Uint8List(0);
    final length = cleanHex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
