import 'dart:typed_data';

class NbgiAccessCodeResult {
  const NbgiAccessCodeResult(this.accessCode, this.serial);

  final String accessCode;
  final int serial;

  @override
  String toString() => "('$accessCode', $serial)";
}

NbgiAccessCodeResult? nbgiGetAccessCode(Uint8List headerData) {
  return null;
}
