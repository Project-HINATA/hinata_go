import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/mifare_write_payload.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';

void main() {
  final id = Uint8List.fromList([1, 2, 3, 4]);

  test('builds Aime writable and permanent payloads', () {
    final accessCode = Uint8List.fromList(List.generate(10, (index) => index));
    final card = Aime(id, 0x08, 0x0004, accessCode);

    final writable = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.rewritable,
    );
    final permanent = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.permanentlyReadOnly,
    );

    expect(writable.profile, MifareWriteProfile.aimeKeyB);
    expect(writable.dataBlocks.keys, [2]);
    expect(writable.dataBlocks[2], [...List.filled(6, 0), ...accessCode]);
    expect(writable.trailer.sublist(6, 10), [0x0f, 0x00, 0xff, 0x69]);
    expect(permanent.trailer.sublist(6, 10), [0x70, 0xf0, 0xf8, 0x69]);
  });

  test('builds key A Banapass without writing block 2', () {
    final block1 = Uint8List.fromList(List.generate(16, (index) => index));
    final card = Banapass(id, 0x08, 0x0004, block1, null);

    final writable = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.rewritable,
    );
    final permanent = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.permanentlyReadOnly,
    );

    expect(writable.profile, MifareWriteProfile.banapassKeyA);
    expect(writable.dataBlocks.keys, [1]);
    expect(writable.trailer.sublist(6, 10), [0xff, 0x07, 0x80, 0x69]);
    expect(permanent.trailer.sublist(6, 10), [0x0f, 0x0f, 0x0f, 0x69]);
  });

  test('builds dual-key Banapass with both data blocks', () {
    final block1 = Uint8List.fromList(List.generate(16, (index) => index));
    final block2 = Uint8List.fromList(List.generate(16, (index) => 16 + index));
    final card = Banapass(id, 0x08, 0x0004, block1, block2);

    final writable = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.rewritable,
    );
    final permanent = MifareCardWritePayload.fromCard(
      card,
      CardWriteMode.permanentlyReadOnly,
    );

    expect(writable.profile, MifareWriteProfile.banapassDualKey);
    expect(writable.dataBlocks.keys, [1, 2]);
    expect(writable.trailer.sublist(6, 10), [0x7f, 0x07, 0x88, 0x69]);
    expect(permanent.trailer.sublist(6, 10), [0x07, 0x8f, 0x0f, 0x69]);
  });
}
