import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/type4_ndef_tag.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

final _selectApplication = _bytes([
  0x00, 0xA4, 0x04, 0x00, 0x07, //
  0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01, 0x00,
]);

Uint8List _selectFile(int id) =>
    _bytes([0x00, 0xA4, 0x00, 0x0C, 0x02, 0xE1, id]);

Uint8List _readBinary(int offset, int length) =>
    _bytes([0x00, 0xB0, offset >> 8, offset & 0xFF, length]);

void main() {
  final message = Uint8List.fromList(List.generate(120, (i) => i));

  test('serves the capability container and the whole message', () {
    final tag = Type4NdefTag(message);

    expect(tag.process(_selectApplication), [0x90, 0x00]);
    expect(tag.process(_selectFile(0x03)), [0x90, 0x00]);
    final cc = tag.process(_readBinary(0, 15));
    expect(cc.sublist(0, 7), [0x00, 0x0F, 0x20, 0x00, 53, 0x00, 53]);
    expect(cc.sublist(9, 15), [0xE1, 0x04, 0x00, 122, 0x00, 0xFF]);
    expect(cc.sublist(15), [0x90, 0x00]);

    expect(tag.process(_selectFile(0x04)), [0x90, 0x00]);
    expect(tag.process(_readBinary(0, 2)), [0x00, 120, 0x90, 0x00]);
    final read = <int>[];
    for (var offset = 2; offset < 122; offset += 53) {
      final response = tag.process(_readBinary(offset, 255));
      expect(response.sublist(response.length - 2), [0x90, 0x00]);
      read.addAll(response.sublist(0, response.length - 2));
    }
    expect(read, message);
    expect(tag.takeMessageRead(), isTrue);
    expect(tag.takeMessageRead(), isFalse);
  });

  test('advertises and enforces a smaller MLe', () {
    final tag = Type4NdefTag(message, maxRead: 51);
    tag.process(_selectApplication);
    tag.process(_selectFile(0x03));
    expect(tag.process(_readBinary(0, 15))[4], 51);
    tag.process(_selectFile(0x04));
    expect(tag.process(_readBinary(0, 0)).length, 53);
  });

  test('rejects writes, unselected reads and short EF addressing', () {
    final tag = Type4NdefTag(message);
    expect(tag.process(_readBinary(0, 2)), [0x69, 0x86]);
    expect(tag.process(_selectFile(0x04)), [0x69, 0x86]);
    tag.process(_selectApplication);
    expect(tag.process(_selectFile(0x05)), [0x6A, 0x82]);
    tag.process(_selectFile(0x04));
    expect(tag.process(_bytes([0x00, 0xD6, 0, 0, 1, 0])), [0x69, 0x82]);
    expect(tag.process(_bytes([0x00, 0xB0, 0x84, 0, 2])), [0x6B, 0x00]);
    expect(tag.process(_readBinary(122, 1)), [0x6B, 0x00]);

    tag.reset();
    expect(tag.process(_readBinary(0, 2)), [0x69, 0x86]);
  });

  test('a partial read does not count as reading the message', () {
    final tag = Type4NdefTag(message);
    tag.process(_selectApplication);
    tag.process(_selectFile(0x04));
    tag.process(_readBinary(0, 50));
    expect(tag.takeMessageRead(), isFalse);
  });

  test('limits the message to what offset addressing reaches', () {
    expect(() => Type4NdefTag(Uint8List(0)), throwsArgumentError);
    expect(() => Type4NdefTag(Uint8List(0x7FFF)), throwsArgumentError);
    expect(Type4NdefTag(Uint8List(0x7FFE)).ndefFile.length, 0x8000);
  });
}
