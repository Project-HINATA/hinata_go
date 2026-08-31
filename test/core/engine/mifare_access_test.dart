import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

void main() {
  test('round-trips every valid sector access combination', () {
    for (var value = 0; value < 4096; value++) {
      final access = MifareSectorAccess(
        block0: MifareAccessCondition.fromValue(value & 7),
        block1: MifareAccessCondition.fromValue((value >> 3) & 7),
        block2: MifareAccessCondition.fromValue((value >> 6) & 7),
        trailer: MifareAccessCondition.fromValue((value >> 9) & 7),
        gpb: value & 0xff,
      );

      expect(MifareSectorAccess.decode(access.encode()), access);
    }
  });

  test('rejects inconsistent inverted access bits', () {
    expect(
      () => MifareSectorAccess.decode(
        Uint8List.fromList([0x00, 0x07, 0x80, 0x69]),
      ),
      throwsA(isA<MifareAccessFormatException>()),
    );
  });

  test('implements all data-block read and write access rows', () {
    const expected = <int, (bool, bool, bool, bool)>{
      0: (true, true, true, true),
      1: (true, true, false, false),
      2: (true, true, false, false),
      3: (false, true, false, true),
      4: (true, true, false, true),
      5: (false, true, false, false),
      6: (true, true, false, true),
      7: (false, false, false, false),
    };

    for (final entry in expected.entries) {
      final permissions = MifareDataBlockPermissions(
        condition: MifareAccessCondition.fromValue(entry.key),
        keyBMayAuthenticate: true,
      );
      final expectedRow = entry.value;
      expect(
        (
          permissions.allows(MifareKeyType.a, MifareDataOperation.read),
          permissions.allows(MifareKeyType.b, MifareDataOperation.read),
          permissions.allows(MifareKeyType.a, MifareDataOperation.write),
          permissions.allows(MifareKeyType.b, MifareDataOperation.write),
        ),
        expectedRow,
        reason: 'condition ${entry.key}',
      );
    }
  });

  test('implements complete trailer management and Key B auth rows', () {
    for (var value = 0; value < 8; value++) {
      final permissions = MifareTrailerPermissions(
        MifareAccessCondition.fromValue(value),
      );
      expect(permissions.canReadKeyA(MifareKeyType.a), isFalse);
      expect(permissions.canReadKeyA(MifareKeyType.b), isFalse);
      expect(
        permissions.keyBMayAuthenticate,
        value >= 3,
        reason: 'condition $value Key B auth',
      );
      expect(
        permissions.canWriteEntireTrailer(MifareKeyType.a),
        value == 1,
        reason: 'condition $value Key A management',
      );
      expect(
        permissions.canWriteEntireTrailer(MifareKeyType.b),
        value == 3,
        reason: 'condition $value Key B management',
      );
    }
  });

  test('transport configuration grants complete trailer control to key A', () {
    final access = MifareSectorAccess.decode(
      Uint8List.fromList([0xff, 0x07, 0x80, 0x69]),
    );

    expect(access.trailer.toString(), '001');
    expect(
      access.trailerPermissions.canWriteEntireTrailer(MifareKeyType.a),
      isTrue,
    );
    expect(access.trailerPermissions.keyBMayAuthenticate, isFalse);
    expect(
      access
          .permissionsForBlock(1)
          .allows(MifareKeyType.b, MifareDataOperation.write),
      isFalse,
    );
  });

  test(
    'key B managed configuration grants complete trailer control to key B',
    () {
      final access = MifareSectorAccess.decode(
        Uint8List.fromList([0x7f, 0x07, 0x88, 0x69]),
      );

      expect(access.trailer.toString(), '011');
      expect(
        access.trailerPermissions.canWriteEntireTrailer(MifareKeyType.b),
        isTrue,
      );
      expect(access.trailerPermissions.keyBMayAuthenticate, isTrue);
    },
  );
}
