import 'card.dart';

class Iso14443 extends ICCard {
  final int sak;
  final int atqa;
  Iso14443(super.id, this.sak, this.atqa);
  @override
  String get name {
    if (sak == 0x09 && atqa == 0x0004 && id.length == 4) {
      return "MIFARE Mini";
    }
    if (sak == 0x08 && atqa == 0x0004 && id.length == 4) {
      return "MIFARE Classic 1K";
    }
    if (sak == 0x18 && atqa == 0x0002 && id.length == 4) {
      return "MIFARE Classic 4K";
    }
    if (sak == 0x00 && atqa == 0x0044 && id.length == 7) {
      return "MIFARE Ultralight";
    }
    if (sak == 0x20 && atqa == 0x0044 && id.length == 7) {
      return "MIFARE Plus";
    }
    return "Generic ISO14443 Card";
  }

  String get sakDisplay =>
      '0x${sak.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  String get atqaDisplay =>
      '0x${atqa.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'sak': sak, 'atqa': atqa};
  }

  factory Iso14443.fromJson(Map<String, dynamic> json) {
    return Iso14443(
      ICCard.hexToBytes(json['id'] as String? ?? ''),
      json['sak'] as int? ?? 0x08,
      json['atqa'] as int? ?? 0x0004,
    );
  }
}
