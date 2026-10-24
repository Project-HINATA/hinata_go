import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/type3_ndef_tag.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  final idm = _bytes([0x02, 0xFE, 1, 2, 3, 4, 5, 6]);
  final message = _bytes(List.generate(20, (i) => i + 1));

  Uint8List check(List<List<int>> blocks, {int service = 0x000B}) => _bytes([
    0x06,
    ...idm,
    0x01,
    service & 0xFF,
    service >> 8,
    blocks.length,
    for (final block in blocks) ...block,
  ]);

  test('answers NDEF and wildcard polling with its system code', () {
    final tag = Type3NdefTag(message, idm: idm);
    expect(tag.process(_bytes([0x00, 0x12, 0xFC, 0x01, 0x00])), [
      0x01,
      ...idm,
      ...Type3NdefTag.defaultPmm,
      0x12,
      0xFC,
    ]);
    expect(tag.process(_bytes([0x00, 0xFF, 0xFF, 0x00, 0x00]))!.length, 17);
    expect(tag.process(_bytes([0x00, 0x88, 0xB4, 0x01, 0x00])), isNull);
  });

  test('reads the attribute block and the message', () {
    final tag = Type3NdefTag(message, idm: idm);
    final response = tag.process(
      check([
        [0x80, 0x00],
        [0x80, 0x01],
      ]),
    )!;
    expect(response.sublist(0, 12), [0x07, ...idm, 0x00, 0x00, 2]);

    final attribute = response.sublist(12, 28);
    expect(attribute.sublist(0, 14), [
      0x10, 2, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 20, //
    ]);
    final sum = attribute.sublist(0, 14).reduce((a, b) => a + b);
    expect(attribute[14] << 8 | attribute[15], sum);
    expect(response.sublist(28), message.sublist(0, 16));
    expect(tag.takeMessageRead(), isFalse);

    // The three-byte block list element addresses the same blocks.
    final last = tag.process(
      check([
        [0x00, 0x02, 0x00],
      ]),
    )!;
    expect(last.sublist(12, 16), message.sublist(16));
    expect(last.sublist(16), List.filled(12, 0));
    expect(tag.takeMessageRead(), isTrue);
  });

  test('refuses writes, unknown services and out-of-range blocks', () {
    final tag = Type3NdefTag(message, idm: idm);
    expect(tag.process(_bytes([0x08, ...idm, 1, 0x09, 0x00, 1, 0x80, 1])), [
      0x09,
      ...idm,
      0x01,
      0xA5,
    ]);
    expect(
      tag.process(
        check([
          [0x80, 0x00],
        ], service: 0x1234),
      ),
      [0x07, ...idm, 0x01, 0xA6],
    );
    expect(
      tag.process(
        check([
          [0x80, 0x03],
        ]),
      ),
      [0x07, ...idm, 0x01, 0xA8],
    );
    expect(
      tag.process(
        check([
          [0x80, 0x00],
          [0x80, 0x01],
          [0x80, 0x02],
        ]),
      ),
      [0x07, ...idm, 0x01, 0xA2],
    );
  });

  test('ignores commands for another IDm', () {
    final tag = Type3NdefTag(message, idm: idm);
    final other = _bytes([0x06, ...List.filled(8, 0), 1, 0x0B, 0, 1, 0x80, 0]);
    expect(tag.process(other), isNull);
  });

  test('reports its NDEF system code and services', () {
    final tag = Type3NdefTag(message, idm: idm);
    expect(tag.process(_bytes([0x0C, ...idm])), [
      0x0D,
      ...idm,
      0x01,
      0x12,
      0xFC,
    ]);
    expect(tag.process(_bytes([0x02, ...idm, 2, 0x0B, 0x00, 0x34, 0x12])), [
      0x03,
      ...idm,
      2,
      0x00,
      0x00,
      0xFF,
      0xFF,
    ]);
  });

  test('random IDm marks a Type 3 tag, not an NFC-DEP target', () {
    final generated = Type3NdefTag.randomIdm(Random(1));
    expect(generated.length, 8);
    expect(generated.sublist(0, 2), [0x02, 0xFE]);
  });
}
