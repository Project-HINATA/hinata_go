import 'dart:typed_data';

class NfcTarget {
  final Uint8List id;
  // Type A specific attributes
  final int? sak;
  final int? atqa;
  // FeliCa specific attributes
  final Uint8List? pmm;
  final Uint16List? systemCodes;

  const NfcTarget({
    required this.id,
    this.sak,
    this.atqa,
    this.pmm,
    this.systemCodes,
  });
}
