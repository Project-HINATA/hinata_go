import 'dart:typed_data';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../models/card/aime.dart';
import '../../models/card/banapass.dart';
import '../../models/card/card.dart';
import '../crypto/mifare_key.dart';

enum CardWriteMode { rewritable, permanentlyReadOnly }

enum MifareWriteProfile { aimeKeyB, banapassKeyA, banapassDualKey }

class MifareCredential {
  final MifareKeyType type;
  final Uint8List value;

  MifareCredential(this.type, List<int> value)
    : value = Uint8List.fromList(value);
}

class MifareWritePayloadException implements Exception {
  final String message;

  const MifareWritePayloadException(this.message);

  @override
  String toString() => 'MifareWritePayloadException: $message';
}

class MifareCardWritePayload {
  static const _defaultKey = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

  final MifareWriteProfile profile;
  final CardWriteMode mode;
  final Map<int, Uint8List> dataBlocks;
  final Uint8List trailer;
  final List<MifareCredential> finalCredentials;
  final MifareSectorAccess finalAccess;

  MifareCardWritePayload({
    required this.profile,
    required this.mode,
    required Map<int, Uint8List> dataBlocks,
    required Uint8List trailer,
    required List<MifareCredential> finalCredentials,
    required this.finalAccess,
  }) : dataBlocks = Map.unmodifiable(
         dataBlocks.map(
           (block, data) => MapEntry(block, Uint8List.fromList(data)),
         ),
       ),
       trailer = Uint8List.fromList(trailer),
       finalCredentials = List.unmodifiable(finalCredentials);

  static MifareCardWritePayload fromCard(ICCard card, CardWriteMode mode) {
    if (card is Aime) return _fromAime(card, mode);
    if (card is Banapass) return _fromBanapass(card, mode);
    throw const MifareWritePayloadException(
      'Only saved Aime and Banapass cards can be written',
    );
  }

  static bool canBuild(ICCard card) {
    try {
      fromCard(card, CardWriteMode.rewritable);
      return true;
    } catch (_) {
      return false;
    }
  }

  static MifareCardWritePayload _fromAime(Aime card, CardWriteMode mode) {
    if (card.accessCode.length != 10) {
      throw const MifareWritePayloadException(
        'Aime access code must contain exactly 10 bytes',
      );
    }

    final block2 = Uint8List(16);
    block2.setRange(6, 16, card.accessCode);
    final dataCondition = MifareAccessCondition.fromValue(
      mode == CardWriteMode.rewritable ? 3 : 5,
    );
    final access = MifareSectorAccess(
      block0: dataCondition,
      block1: dataCondition,
      block2: dataCondition,
      trailer: MifareAccessCondition.fromValue(
        mode == CardWriteMode.rewritable ? 3 : 7,
      ),
    );

    return MifareCardWritePayload(
      profile: MifareWriteProfile.aimeKeyB,
      mode: mode,
      dataBlocks: {2: block2},
      trailer: _buildTrailer(_defaultKey, access, aimeKey),
      finalCredentials: [MifareCredential(MifareKeyType.b, aimeKey)],
      finalAccess: access,
    );
  }

  static MifareCardWritePayload _fromBanapass(
    Banapass card,
    CardWriteMode mode,
  ) {
    if (card.block1.length != 16) {
      throw const MifareWritePayloadException(
        'Banapass block 1 must contain exactly 16 bytes',
      );
    }
    if (card.block2 != null && card.block2!.length != 16) {
      throw const MifareWritePayloadException(
        'Banapass block 2 must contain exactly 16 bytes when present',
      );
    }

    final dualKey = card.block2 != null;
    final access = MifareSectorAccess(
      block0: MifareAccessCondition.fromValue(
        mode == CardWriteMode.rewritable ? 0 : 2,
      ),
      block1: MifareAccessCondition.fromValue(
        mode == CardWriteMode.rewritable ? 0 : 2,
      ),
      block2: MifareAccessCondition.fromValue(
        mode == CardWriteMode.rewritable ? 0 : 2,
      ),
      trailer: MifareAccessCondition.fromValue(
        mode == CardWriteMode.rewritable
            ? (dualKey ? 3 : 1)
            : (dualKey ? 6 : 2),
      ),
    );
    final blocks = <int, Uint8List>{1: Uint8List.fromList(card.block1)};
    if (card.block2 case final block2?) {
      blocks[2] = Uint8List.fromList(block2);
    }

    return MifareCardWritePayload(
      profile: dualKey
          ? MifareWriteProfile.banapassDualKey
          : MifareWriteProfile.banapassKeyA,
      mode: mode,
      dataBlocks: blocks,
      trailer: _buildTrailer(banaKey, access, dualKey ? aimeKey : _defaultKey),
      finalCredentials: [
        MifareCredential(MifareKeyType.a, banaKey),
        if (dualKey) MifareCredential(MifareKeyType.b, aimeKey),
      ],
      finalAccess: access,
    );
  }

  static Uint8List _buildTrailer(
    List<int> keyA,
    MifareSectorAccess access,
    List<int> keyB,
  ) {
    final trailer = BytesBuilder(copy: false)
      ..add(keyA)
      ..add(access.encode())
      ..add(keyB);
    final bytes = trailer.toBytes();
    if (bytes.length != 16) {
      throw const MifareWritePayloadException(
        'Mifare trailer must contain exactly 16 bytes',
      );
    }
    return bytes;
  }
}
