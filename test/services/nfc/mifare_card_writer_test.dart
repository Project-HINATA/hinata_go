import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/engine/mifare_write_payload.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/banapass.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/services/nfc/mifare_card_writer.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

void main() {
  final tag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x08, 0x0004);

  test(
    'writes data before trailer and verifies Aime with final Key B',
    () async {
      final channel = _MemoryMifareChannel.transportConfiguration();
      final card = Aime(
        tag.id,
        tag.sak,
        tag.atqa,
        Uint8List.fromList(List.generate(10, (index) => index + 1)),
      );
      final payload = MifareCardWritePayload.fromCard(
        card,
        CardWriteMode.rewritable,
      );

      await MifareCardWriter(channel: channel, tag: tag).write(payload);

      expect(channel.writeOrder, [2, 3]);
      expect(channel.blocks[2], payload.dataBlocks[2]);
      expect(channel.access, payload.finalAccess);
      expect(channel.successfulAuthTypes.last, MifareKeyType.b);
    },
  );

  test(
    'writes both Banapass data blocks before its dual-key trailer',
    () async {
      final channel = _MemoryMifareChannel.transportConfiguration();
      final card = Banapass(
        tag.id,
        tag.sak,
        tag.atqa,
        Uint8List.fromList(List.generate(16, (index) => index)),
        Uint8List.fromList(List.generate(16, (index) => index + 16)),
      );
      final payload = MifareCardWritePayload.fromCard(
        card,
        CardWriteMode.permanentlyReadOnly,
      );

      await MifareCardWriter(channel: channel, tag: tag).write(payload);

      expect(channel.writeOrder, [1, 2, 3]);
      expect(channel.access, payload.finalAccess);
      expect(
        channel.successfulAuthTypes,
        containsAll([MifareKeyType.a, MifareKeyType.b]),
      );
    },
  );

  test(
    'does not write when no known key can manage the entire update',
    () async {
      final access = MifareSectorAccess(
        block0: MifareAccessCondition.fromValue(0),
        block1: MifareAccessCondition.fromValue(0),
        block2: MifareAccessCondition.fromValue(0),
        trailer: MifareAccessCondition.fromValue(3),
      );
      final channel = _MemoryMifareChannel(
        keyA: _MemoryMifareChannel.defaultKey,
        keyB: const [1, 1, 1, 1, 1, 1],
        access: access,
      );
      final card = Aime(
        tag.id,
        tag.sak,
        tag.atqa,
        Uint8List.fromList(List.filled(10, 7)),
      );

      await expectLater(
        MifareCardWriter(channel: channel, tag: tag).write(
          MifareCardWritePayload.fromCard(card, CardWriteMode.rewritable),
        ),
        throwsA(
          isA<MifareCardWriteException>().having(
            (error) => error.failure,
            'failure',
            MifareWriteFailure.permissionDenied,
          ),
        ),
      );
      expect(channel.writeOrder, isEmpty);
    },
  );

  test('honors cancellation after preflight and before writing', () async {
    final channel = _MemoryMifareChannel.transportConfiguration();
    final card = Aime(
      tag.id,
      tag.sak,
      tag.atqa,
      Uint8List.fromList(List.filled(10, 7)),
    );
    var cancelled = false;

    await expectLater(
      MifareCardWriter(channel: channel, tag: tag).write(
        MifareCardWritePayload.fromCard(card, CardWriteMode.rewritable),
        onStage: (stage) {
          if (stage == MifareWriteStage.checkingPermissions) cancelled = true;
        },
        isCancelled: () => cancelled,
      ),
      throwsA(
        isA<MifareCardWriteException>().having(
          (error) => error.failure,
          'failure',
          MifareWriteFailure.cancelled,
        ),
      ),
    );
    expect(channel.writeOrder, isEmpty);
  });

  test(
    'rejects targets other than MIFARE Classic 1K before authentication',
    () async {
      final channel = _MemoryMifareChannel.transportConfiguration();
      final wrongTag = Iso14443(Uint8List.fromList([1, 2, 3, 4]), 0x18, 0x0002);
      final card = Aime(
        tag.id,
        tag.sak,
        tag.atqa,
        Uint8List.fromList(List.filled(10, 7)),
      );

      await expectLater(
        MifareCardWriter(channel: channel, tag: wrongTag).write(
          MifareCardWritePayload.fromCard(card, CardWriteMode.rewritable),
        ),
        throwsA(
          isA<MifareCardWriteException>().having(
            (error) => error.failure,
            'failure',
            MifareWriteFailure.unsupportedCard,
          ),
        ),
      );
      expect(channel.authAttempts, 0);
    },
  );
}

class _MemoryMifareChannel implements NfcCardChannel {
  static const defaultKey = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

  List<int> keyA;
  List<int> keyB;
  MifareSectorAccess access;
  final blocks = <int, Uint8List>{
    0: Uint8List(16),
    1: Uint8List(16),
    2: Uint8List(16),
  };
  final writeOrder = <int>[];
  final successfulAuthTypes = <MifareKeyType>[];
  MifareKeyType? _authenticatedType;
  var authAttempts = 0;

  _MemoryMifareChannel({
    required List<int> keyA,
    required List<int> keyB,
    required this.access,
  }) : keyA = List.of(keyA),
       keyB = List.of(keyB);

  factory _MemoryMifareChannel.transportConfiguration() {
    return _MemoryMifareChannel(
      keyA: defaultKey,
      keyB: defaultKey,
      access: MifareSectorAccess(
        block0: MifareAccessCondition.fromValue(0),
        block1: MifareAccessCondition.fromValue(0),
        block2: MifareAccessCondition.fromValue(0),
        trailer: MifareAccessCondition.fromValue(1),
      ),
    );
  }

  @override
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  }) async {
    authAttempts++;
    final type = keyA != null ? MifareKeyType.a : MifareKeyType.b;
    final supplied = keyA ?? keyB!;
    final expected = type == MifareKeyType.a ? this.keyA : this.keyB;
    final mayAuthenticate =
        type == MifareKeyType.a ||
        access.trailerPermissions.keyBMayAuthenticate;
    if (!mayAuthenticate || !_equal(supplied, expected)) {
      throw NfcException(type: NfcErrorType.authFailed, message: 'Wrong key');
    }
    _authenticatedType = type;
    successfulAuthTypes.add(type);
  }

  @override
  Future<Uint8List> readMifareBlock(int block) async {
    if (_authenticatedType == null) throw StateError('Not authenticated');
    if (block != 3) return Uint8List.fromList(blocks[block]!);
    return Uint8List.fromList([...keyA, ...access.encode(), ...keyB]);
  }

  @override
  Future<void> writeMifareBlock(int block, Uint8List data) async {
    final type = _authenticatedType;
    if (type == null) throw StateError('Not authenticated');
    if (block == 3) {
      if (!access.trailerPermissions.canWriteEntireTrailer(type)) {
        throw StateError('Trailer denied');
      }
      keyA = data.sublist(0, 6);
      access = MifareSectorAccess.decode(data);
      keyB = data.sublist(10, 16);
    } else {
      final allowed = access
          .permissionsForBlock(block)
          .allows(type, MifareDataOperation.write);
      if (!allowed) throw StateError('Block denied');
      blocks[block] = Uint8List.fromList(data);
    }
    writeOrder.add(block);
  }

  @override
  Future<void> reconnect() async {
    _authenticatedType = null;
  }

  @override
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout}) async {
    throw UnsupportedError('Not used');
  }

  @override
  Future<void> close() async {}

  bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
