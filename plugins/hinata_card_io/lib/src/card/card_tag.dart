import 'dart:typed_data';

abstract class CardTag {
  const CardTag(this.id);

  final Uint8List id;

  String get idString =>
      id.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class FelicaTag extends CardTag {
  const FelicaTag(super.id, this.pmm, this.systemCode);

  final Uint8List pmm;
  final Uint16List systemCode;

  String get pmmString =>
      pmm.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  String get systemCodeDisplay => systemCode
      .map((code) => code.toRadixString(16).padLeft(4, '0').toUpperCase())
      .join(', ');
}

class Iso14443aTag extends CardTag {
  const Iso14443aTag(super.id, this.sak, this.atqa);

  final int sak;
  final int atqa;

  bool get isMifareClassicCandidate => (sak & 0x08) != 0;

  String get sakDisplay =>
      '0x${sak.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  String get atqaDisplay =>
      '0x${atqa.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

class Iso15693Tag extends CardTag {
  const Iso15693Tag(super.id);
}
