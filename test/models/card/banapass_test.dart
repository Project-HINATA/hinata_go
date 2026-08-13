import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/card.dart';

void main() {
  final card = Banapass(
    Uint8List.fromList([1, 2, 3, 4]),
    8,
    0x0400,
    Uint8List(16),
    null,
  );

  test('serializes with the Banapass domain type', () {
    expect(card.toJson()['type'], 'banapass');
  });

  test('still reads legacy Mifare payloads', () {
    final decoded = ICCard.fromJson({...card.toJson(), 'type': 'mifare'});

    expect(decoded, isA<Banapass>());
  });
}
