import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/models/card/felica.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/services/nfc/mifare_card_writer.dart';
import 'package:hinata_go/services/nfc/ndef_tag_service.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:ndef/ndef.dart' as ndef;

void main() {
  final message = NdefCard.fromRecords([
    ndef.TextRecord(text: '你好', language: 'zh'),
    ndef.UriRecord.fromString('https://example.org'),
  ]);
  Iso14443 tag([bool large = false]) =>
      Iso14443(Uint8List.fromList([1, 2, 3, 4]), large ? 0x18 : 8, 4);
  Matcher failure(MifareWriteFailure kind) => throwsA(
    isA<MifareCardWriteException>().having((e) => e.failure, 'failure', kind),
  );

  test('MAD CRC matches the standard all-NDEF MAD1 vector', () {
    expect(
      madCrc([
        0,
        for (var i = 0; i < 15; i++) ...[3, 0xe1],
      ]),
      0x0f,
    );
  });
  test('TLV supports extended lengths, NULL and non-NDEF records', () {
    final data = Uint8List.fromList(List.filled(300, 1));
    expect(readNdefTlv(ndefTlv(data)), data);
    expect(
      readNdefTlv(Uint8List.fromList([0, 0xfd, 2, 1, 2, ...ndefTlv(data)])),
      data,
    );
    expect(
      () => readNdefTlv(Uint8List.fromList([3, 255, 1])),
      throwsFormatException,
    );
    expect(
      () => readNdefTlv(Uint8List.fromList([3, 10, 1])),
      throwsFormatException,
    );
  });

  for (final large in [false, true]) {
    test(
      'formats Classic ${large ? '4K' : '1K'} and reads multiple NDEF records back',
      () async {
        final channel = _Classic(large: large);
        final service = NdefTagService(channel);
        final card = large
            ? NdefCard.fromRecords([
                ndef.TextRecord(text: 'x' * 2100, language: 'en'),
              ])
            : message;
        await service.write(tag(large), card);
        final read = (await service.read(tag(large)))!;
        expect(read.message, card.message);
        expect(read.physicalCard!.toJson(), tag(large).toJson());
        expect(read.capacity, large ? 3360 : 720);
        expect(channel.writes, isNot(contains(0)));
        expect(channel.blocks[3]!.sublist(6, 10), [
          0x78,
          0x77,
          0x88,
          large ? 0xc2 : 0xc1,
        ]);
        expect(channel.blocks[7]!.sublist(6, 10), [0x7f, 7, 0x88, 0x40]);
        final before = [...channel.blocks[3]!];
        channel.writes.clear();
        await service.write(tag(large), message);
        expect(channel.blocks[3], before);
        expect(channel.writes.any((b) => _isTrailer(b)), isFalse);
      },
    );
  }
  test(
    'checks every sector before writing even when a late sector has unknown keys',
    () async {
      final channel = _Classic()..unknownSector = 15;
      await expectLater(
        NdefTagService(channel).write(tag(), message),
        failure(MifareWriteFailure.authenticationFailed),
      );
      expect(channel.writes, isEmpty);
    },
  );
  test(
    'refuses to format when an authenticated key cannot replace the trailer',
    () async {
      final channel = _Classic();
      channel.blocks[23]!.setRange(6, 10, _access(0, 7).encode());
      await expectLater(
        NdefTagService(channel).write(tag(), message),
        failure(MifareWriteFailure.permissionDenied),
      );
      expect(channel.writes, isEmpty);
    },
  );
  test(
    'rejects invalid access-bit complements before changing any data',
    () async {
      final channel = _Classic();
      channel.blocks[15]![6] ^= 1;
      await expectLater(
        NdefTagService(channel).write(tag(), message),
        failure(MifareWriteFailure.invalidAccessBits),
      );
      expect(channel.writes, isEmpty);
    },
  );
  test(
    'checks full payload capacity and cancellation before changing data',
    () async {
      final channel = _Classic();
      await expectLater(
        NdefTagService(channel).write(
          tag(),
          NdefCard.fromRecords([
            ndef.TextRecord(text: 'x' * 800, language: 'en'),
          ]),
        ),
        failure(MifareWriteFailure.capacityExceeded),
      );
      await expectLater(
        NdefTagService(channel).write(tag(), message, isCancelled: () => true),
        failure(MifareWriteFailure.cancelled),
      );
      expect(channel.writes, isEmpty);
    },
  );
  for (final large in [false, true]) {
    test(
      'locks a freshly formatted Classic ${large ? '4K' : '1K'} read-only after verifying it',
      () async {
        final channel = _Classic(large: large);
        final service = NdefTagService(channel);
        await service.write(tag(large), message, readOnly: true);

        expect((await service.read(tag(large)))!.message, message.message);
        final lastData = channel.writes.lastIndexWhere((b) => !_isTrailer(b));
        final ndefTrailers = [
          for (var s = 1; s < (large ? 40 : 16); s++)
            if (s != 16) s < 32 ? s * 4 + 3 : 128 + (s - 32) * 16 + 15,
        ];
        final madTrailers = [3, if (large) 67];
        for (final trailer in ndefTrailers) {
          expect(channel.blocks[trailer]!.sublist(0, 10), [
            0xd3, 0xf7, 0xd3, 0xf7, 0xd3, 0xf7, 0x07, 0x8f, 0x0f, 0x43, //
          ]);
        }
        expect(channel.blocks[3]!.sublist(0, 10), [
          0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0x07, 0x8f, 0x0f, //
          large ? 0xc2 : 0xc1,
        ]);
        if (large) expect(channel.blocks[67]!.sublist(6, 10), [7, 0x8f, 15, 0]);
        // The directory is locked last, after every NDEF sector.
        expect(channel.writes.lastWhere(_isTrailer), madTrailers.last);
        expect(
          channel.writes.indexOf(ndefTrailers.first, lastData),
          greaterThan(lastData),
        );

        channel.writes.clear();
        await expectLater(
          service.write(tag(large), message),
          failure(MifareWriteFailure.permissionDenied),
        );
        expect(channel.writes, isEmpty);
      },
    );
  }
  test('locks an already formatted Classic card in place', () async {
    final channel = _Classic();
    final service = NdefTagService(channel);
    await service.write(tag(), message);
    channel.writes.clear();
    final card = NdefCard.fromRecords([
      ndef.UriRecord.fromString('https://example.org/locked'),
    ]);
    await service.write(tag(), card, readOnly: true);
    expect((await service.read(tag()))!.message, card.message);
    expect(channel.blocks[3]!.sublist(6, 10), [7, 0x8f, 15, 0xc1]);
    expect(channel.blocks[7]!.sublist(6, 10), [7, 0x8f, 15, 0x43]);
    expect(channel.blocks[63]!.sublist(6, 10), [7, 0x8f, 15, 0x43]);
  });
  test(
    'refuses to lock before writing when a directory trailer cannot be rewritten',
    () async {
      final channel = _Classic();
      final service = NdefTagService(channel);
      await service.write(tag(), message);
      channel.blocks[3]!.setRange(
        6,
        10,
        MifareSectorAccess(
          block0: MifareAccessCondition.fromValue(4),
          block1: MifareAccessCondition.fromValue(4),
          block2: MifareAccessCondition.fromValue(4),
          trailer: MifareAccessCondition.fromValue(6),
          gpb: 0xc1,
        ).encode(),
      );
      channel.writes.clear();
      await expectLater(
        service.write(tag(), message, readOnly: true),
        failure(MifareWriteFailure.permissionDenied),
      );
      expect(channel.writes, isEmpty);
    },
  );
  test('detects failed Classic writes through read-back', () async {
    final channel = _Classic()..dropWrites = true;
    await expectLater(
      NdefTagService(channel).write(tag(), message),
      failure(MifareWriteFailure.verificationFailed),
    );
  });

  test('leaves a FeliCa card to the block read', () async {
    final tag = Felica(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      Uint8List(8),
      Uint16List.fromList([0x12fc]),
    );
    final channel = _ScriptChannel((command) {
      fail('Sent ${command.length} bytes to a FeliCa card');
    });
    expect(await NdefTagService(channel).read(tag), isNull);
  });
  test('reads Type 4 CC, NLEN and bounded READ BINARY chunks', () async {
    final card = NdefCard.fromRecords([
      ndef.TextRecord(text: 'x' * 300, language: 'en'),
    ]);
    final file = Uint8List.fromList([
      card.message.length >> 8,
      card.message.length & 255,
      ...card.message,
    ]);
    var selectedFile = 0;
    final channel = _ScriptChannel((command) {
      if (command[1] == 0xa4) {
        if (command[2] == 0) selectedFile = (command[5] << 8) | command[6];
        return Uint8List.fromList([0x90, 0]);
      }
      expect(command[1], 0xb0);
      if (selectedFile == 0xe103) {
        return Uint8List.fromList([
          0,
          15,
          0x20,
          0,
          0x80,
          0,
          0xff,
          4,
          6,
          0xe1,
          4,
          4,
          0,
          0,
          0,
          0x90,
          0,
        ]);
      }
      final offset = (command[2] << 8) | command[3];
      return Uint8List.fromList([
        ...file.sublist(offset, offset + command[4]),
        0x90,
        0,
      ]);
    });
    final read = (await NdefTagService(
      channel,
    ).read(Iso14443(Uint8List(7), 0x20, 0x44)))!;
    expect(read.message, card.message);
    expect(read.capacity, 1022);
  });

  final ntag = Iso14443(Uint8List.fromList([4, 1, 2, 3, 4, 5, 6]), 0, 0x44);
  test(
    'writes NTAG with length published last and leaves lock/config pages untouched',
    () async {
      final channel = _Ntag();
      await NdefTagService(channel).write(ntag, message);
      final read = (await NdefTagService(channel).read(ntag))!;
      expect(read.message, message.message);
      expect(read.capacity, 144);
      expect(read.physicalCard, same(ntag));
      expect(channel.writes.first, 4);
      expect(channel.writes.last, 4);
      expect(channel.writes.every((p) => p >= 4 && p < 40), isTrue);
      expect(channel.memory[10], 0);
      expect(channel.memory[40 * 4], 0);
    },
  );
  for (final (storage, dynamicPage, locks) in [
    (0x0f, 0x28, [0xff, 0x0f, 0x3f]),
    (0x11, 0x82, [0xff, 0x00, 0x0f]),
    (0x13, 0xe2, [0xff, 0x3f, 0x7f]),
  ]) {
    test(
      'locks NTAG with storage $storage read-only after verifying it',
      () async {
        final channel = _Ntag(dynamicPage: dynamicPage)..storage = storage;
        final service = NdefTagService(channel);
        await service.write(ntag, message, readOnly: true);

        expect((await service.read(ntag))!.message, message.message);
        // CC first, while page 3 can still be written; static locks last.
        expect(channel.writes.sublist(channel.writes.length - 3), [
          3,
          dynamicPage,
          2,
        ]);
        expect(channel.memory.sublist(8, 16), [
          0x56, 0x78, 0xff, 0xff, 0xe1, 0x10, 0x12, 0x0f, //
        ]);
        expect(channel.memory.sublist(dynamicPage * 4, dynamicPage * 4 + 4), [
          ...locks,
          0xbd,
        ]);

        channel.writes.clear();
        await expectLater(
          service.write(ntag, message),
          failure(MifareWriteFailure.permissionDenied),
        );
        expect(channel.writes, isEmpty);
      },
    );
  }
  test('does not lock NTAG whose content fails verification', () async {
    final channel = _Ntag()..dropDataWrites = true;
    await expectLater(
      NdefTagService(channel).write(ntag, message, readOnly: true),
      failure(MifareWriteFailure.verificationFailed),
    );
    expect(channel.writes, isNot(contains(2)));
    expect(channel.writes, isNot(contains(3)));
    expect(channel.memory[15], 0);
  });
  for (final location in [10, 11, 15, 160, 161, 162, 167]) {
    test(
      'rejects NTAG lock/protection byte at $location without writes',
      () async {
        final channel = _Ntag();
        channel.memory[location] = location == 167 ? 4 : 1;
        await expectLater(
          NdefTagService(channel).write(ntag, message),
          failure(MifareWriteFailure.permissionDenied),
        );
        expect(channel.writes, isEmpty);
      },
    );
  }
  test(
    'rejects unknown NTAG models, oversized payloads and reserved TLVs',
    () async {
      final channel = _Ntag()..storage = 0x10;
      await expectLater(
        NdefTagService(channel).write(ntag, message),
        failure(MifareWriteFailure.unsupportedCard),
      );
      channel.storage = 15;
      await expectLater(
        NdefTagService(channel).write(
          ntag,
          NdefCard.fromRecords([
            ndef.TextRecord(text: 'x' * 200, language: 'en'),
          ]),
        ),
        failure(MifareWriteFailure.capacityExceeded),
      );
      channel.memory[16] = 1;
      await expectLater(
        NdefTagService(channel).write(ntag, message),
        failure(MifareWriteFailure.unsupportedCard),
      );
      expect(channel.writes, isEmpty);
    },
  );
}

bool _isTrailer(int block) =>
    block < 128 ? block % 4 == 3 : (block - 128) % 16 == 15;
int _sector(int block) => block < 128 ? block ~/ 4 : 32 + (block - 128) ~/ 16;
MifareSectorAccess _access(int data, int trailer) => MifareSectorAccess(
  block0: MifareAccessCondition.fromValue(data),
  block1: MifareAccessCondition.fromValue(data),
  block2: MifareAccessCondition.fromValue(data),
  trailer: MifareAccessCondition.fromValue(trailer),
);

class _Classic implements NfcCardChannel {
  final blocks = <int, Uint8List>{};
  final writes = <int>[];
  int? unknownSector;
  bool dropWrites = false;
  int? activeSector;
  MifareKeyType? activeKey;
  _Classic({bool large = false}) {
    for (var b = 0; b < (large ? 256 : 64); b++) {
      blocks[b] = Uint8List(16);
      if (_isTrailer(b)) {
        blocks[b]!.setAll(0, [
          ...List.filled(6, 255),
          ..._access(0, 1).encode(),
          ...List.filled(6, 255),
        ]);
      }
    }
  }
  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) async {
    final sector = _sector(block);
    final trailer =
        blocks[sector < 32 ? sector * 4 + 3 : 128 + (sector - 32) * 16 + 15]!;
    final type = keyA != null ? MifareKeyType.a : MifareKeyType.b;
    final access = MifareSectorAccess.decode(trailer);
    if (unknownSector == sector ||
        !listEquals(
          keyA ?? keyB,
          trailer.sublist(
            type == MifareKeyType.a ? 0 : 10,
            type == MifareKeyType.a ? 6 : 16,
          ),
        ) ||
        (type == MifareKeyType.b &&
            !access.trailerPermissions.keyBMayAuthenticate)) {
      throw NfcException(type: NfcErrorType.authFailed, message: 'Unknown key');
    }
    activeSector = sector;
    activeKey = type;
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    if (activeSector != _sector(block)) throw StateError('Wrong sector');
    final result = Uint8List.fromList(blocks[block]!);
    if (_isTrailer(block)) {
      result.fillRange(0, 6, 0);
      if (!MifareSectorAccess.decode(
        result,
      ).trailerPermissions.canReadKeyB(activeKey!)) {
        result.fillRange(10, 16, 0);
      }
    }
    return result;
  }

  @override
  Future<void> writeMifareBlock(int block, Uint8List data) async {
    if (activeSector != _sector(block)) throw StateError('Wrong sector');
    final trailer =
        blocks[block < 128
            ? block ~/ 4 * 4 + 3
            : 128 + (block - 128) ~/ 16 * 16 + 15]!;
    final access = MifareSectorAccess.decode(trailer);
    final group = block < 128 ? block % 4 : (block - 128) % 16 ~/ 5;
    if (_isTrailer(block)
        ? !access.trailerPermissions.canWriteEntireTrailer(activeKey!)
        : !access
              .permissionsForBlock(group)
              .allows(activeKey!, MifareDataOperation.write)) {
      throw StateError('Write not allowed');
    }
    writes.add(block);
    if (!dropWrites) blocks[block] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) =>
      throw UnimplementedError();
  @override
  Future<void> reconnect() async {
    activeSector = null;
    activeKey = null;
  }

  @override
  Future<void> close() async {}
}

/// NTAG21x memory with the chip's write rules: the lock bytes and CC are
/// OR'ed in, page 2 bytes 0-1 and dynamic lock byte 3 ignore writes.
class _Ntag implements NfcCardChannel {
  final int dynamicPage;
  final Uint8List memory;
  final writes = <int>[];
  int storage = 15;
  bool dropDataWrites = false;
  _Ntag({this.dynamicPage = 0x28}) : memory = Uint8List(dynamicPage * 4 + 20) {
    memory.setRange(8, 10, [0x56, 0x78]);
    memory.setRange(12, 16, [0xe1, 0x10, 0x12, 0]);
    memory[16] = 3;
    memory[18] = 0xfe;
    memory[dynamicPage * 4 + 3] = 0xbd;
    memory[dynamicPage * 4 + 7] = 255;
  }
  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    if (data[0] == 0x60) {
      return Uint8List.fromList([0, 4, 4, 2, 1, 0, storage, 3]);
    }
    if (data[0] == 0x30) {
      return Uint8List.fromList([
        for (var i = 0; i < 16; i++) memory[(data[1] * 4 + i) % memory.length],
      ]);
    }
    if (data[0] == 0xa2) {
      final page = data[1];
      final start = page * 4;
      final staticLocked = memory[10] == 0xff && memory[11] == 0xff;
      if (staticLocked && page >= 3 && page < 16) {
        return Uint8List.fromList([0]);
      }
      writes.add(page);
      if (page == 2) {
        memory[10] |= data[4];
        memory[11] |= data[5];
      } else if (page == 3) {
        for (var i = 0; i < 4; i++) {
          memory[start + i] |= data[2 + i];
        }
      } else if (page == dynamicPage) {
        for (var i = 0; i < 3; i++) {
          memory[start + i] |= data[2 + i];
        }
      } else if (!dropDataWrites) {
        memory.setRange(start, start + 4, data.sublist(2));
      }
      return Uint8List.fromList([0x0a]);
    }
    throw StateError('Unexpected command');
  }

  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) => throw UnimplementedError();
  @override
  Future<Uint8List> readMifareBlock(int block) => throw UnimplementedError();
  @override
  Future<void> writeMifareBlock(int block, Uint8List data) =>
      throw UnimplementedError();
  @override
  Future<void> reconnect() async {}
  @override
  Future<void> close() async {}
}

class _ScriptChannel implements NfcCardChannel {
  final Uint8List Function(Uint8List) respond;
  _ScriptChannel(this.respond);
  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async =>
      respond(data);
  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) => throw UnimplementedError();
  @override
  Future<Uint8List> readMifareBlock(int block) => throw UnimplementedError();
  @override
  Future<void> writeMifareBlock(int block, Uint8List data) =>
      throw UnimplementedError();
  @override
  Future<void> reconnect() async {}
  @override
  Future<void> close() async {}
}
