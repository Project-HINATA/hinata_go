import 'dart:typed_data';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../core/crypto/mifare_key.dart';
import '../../core/engine/mifare_write_payload.dart';
import '../../models/card/iso14443a.dart';

enum MifareWriteStage {
  checkingCard,
  checkingPermissions,
  writingData,
  lockingCard,
  verifying,
}

enum MifareWriteFailure {
  unsupportedCard,
  authenticationFailed,
  invalidAccessBits,
  permissionDenied,
  cardRemoved,
  writeFailed,
  verificationFailed,
  cancelled,
}

class MifareCardWriteException implements Exception {
  final MifareWriteFailure failure;
  final String message;
  final Object? cause;

  const MifareCardWriteException(this.failure, this.message, {this.cause});

  @override
  String toString() => 'MifareCardWriteException($failure): $message';
}

typedef MifareWriteStageCallback = void Function(MifareWriteStage stage);

class MifareCardWriter {
  static const _defaultKey = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

  final NfcCardChannel channel;
  final Iso14443 tag;

  MifareCardWriter({required this.channel, required this.tag});

  Future<void> write(
    MifareCardWritePayload payload, {
    MifareWriteStageCallback? onStage,
    bool Function()? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    onStage?.call(MifareWriteStage.checkingCard);
    _validateTarget();

    onStage?.call(MifareWriteStage.checkingPermissions);
    final manager = await _findManagingCredential(payload);
    if (manager == null) {
      throw const MifareCardWriteException(
        MifareWriteFailure.permissionDenied,
        'No known key can write every requested block and the complete trailer',
      );
    }

    _throwIfCancelled(isCancelled);
    onStage?.call(MifareWriteStage.writingData);
    for (final entry in payload.dataBlocks.entries) {
      await _writeAndVerify(entry.key, entry.value);
    }

    onStage?.call(MifareWriteStage.lockingCard);
    try {
      await channel.writeMifareBlock(3, payload.trailer);
    } catch (error) {
      throw MifareCardWriteException(
        MifareWriteFailure.writeFailed,
        'Failed to write the sector trailer',
        cause: error,
      );
    }

    onStage?.call(MifareWriteStage.verifying);
    await _verifyFinalState(payload);
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const MifareCardWriteException(
        MifareWriteFailure.cancelled,
        'Card writing was cancelled before data was changed',
      );
    }
  }

  void _validateTarget() {
    if (tag.sak != 0x08 || tag.id.length != 4) {
      throw const MifareCardWriteException(
        MifareWriteFailure.unsupportedCard,
        'The detected tag is not a MIFARE Classic 1K card with a 4-byte UID',
      );
    }
  }

  Future<MifareCredential?> _findManagingCredential(
    MifareCardWritePayload payload,
  ) async {
    final candidates = <MifareCredential>[
      MifareCredential(MifareKeyType.a, _defaultKey),
      MifareCredential(MifareKeyType.b, _defaultKey),
      MifareCredential(MifareKeyType.a, banaKey),
      MifareCredential(MifareKeyType.b, aimeKey),
    ];

    var authenticatedAny = false;
    var decodedAny = false;
    for (final credential in candidates) {
      try {
        await _authenticate(credential);
        authenticatedAny = true;
        final trailer = await channel.readMifareBlock(3);
        final access = MifareSectorAccess.decode(trailer);
        decodedAny = true;

        final canWriteData = payload.dataBlocks.keys.every(
          (block) => access
              .permissionsForBlock(block)
              .allows(credential.type, MifareDataOperation.write),
        );
        final canWriteTrailer = access.trailerPermissions.canWriteEntireTrailer(
          credential.type,
        );
        if (canWriteData && canWriteTrailer) return credential;
      } on MifareAccessFormatException catch (error) {
        throw MifareCardWriteException(
          MifareWriteFailure.invalidAccessBits,
          'The sector trailer contains invalid access bits',
          cause: error,
        );
      } catch (_) {
        // A failed key is expected while probing the small known-key set.
      }

      try {
        await channel.reconnect();
      } catch (_) {
        throw const MifareCardWriteException(
          MifareWriteFailure.cardRemoved,
          'The card was removed during permission checks',
        );
      }
    }

    if (!authenticatedAny) {
      throw const MifareCardWriteException(
        MifareWriteFailure.authenticationFailed,
        'None of the supported keys can authenticate sector 0',
      );
    }
    if (!decodedAny) {
      throw const MifareCardWriteException(
        MifareWriteFailure.invalidAccessBits,
        'The sector access bits could not be read',
      );
    }
    return null;
  }

  Future<void> _authenticate(MifareCredential credential) async {
    await channel.authenticateMifare(
      uid: Uint8List.fromList(tag.id),
      block: 3,
      keyA: credential.type == MifareKeyType.a ? credential.value : null,
      keyB: credential.type == MifareKeyType.b ? credential.value : null,
    );
  }

  Future<void> _writeAndVerify(int block, Uint8List expected) async {
    try {
      await channel.writeMifareBlock(block, expected);
      final actual = await channel.readMifareBlock(block);
      if (!_bytesEqual(actual, expected)) {
        throw MifareCardWriteException(
          MifareWriteFailure.verificationFailed,
          'Block $block did not match after writing',
        );
      }
    } on MifareCardWriteException {
      rethrow;
    } catch (error) {
      throw MifareCardWriteException(
        MifareWriteFailure.writeFailed,
        'Failed to write block $block',
        cause: error,
      );
    }
  }

  Future<void> _verifyFinalState(MifareCardWritePayload payload) async {
    for (final credential in payload.finalCredentials) {
      try {
        await channel.reconnect();
        await _authenticate(credential);

        for (final entry in payload.dataBlocks.entries) {
          final actual = await channel.readMifareBlock(entry.key);
          if (!_bytesEqual(actual, entry.value)) {
            throw MifareCardWriteException(
              MifareWriteFailure.verificationFailed,
              'Block ${entry.key} failed final verification',
            );
          }
        }

        final trailer = await channel.readMifareBlock(3);
        final finalAccess = MifareSectorAccess.decode(trailer);
        if (finalAccess != payload.finalAccess) {
          throw const MifareCardWriteException(
            MifareWriteFailure.verificationFailed,
            'Final access bits do not match the requested mode',
          );
        }
      } on MifareCardWriteException {
        rethrow;
      } catch (error) {
        throw MifareCardWriteException(
          MifareWriteFailure.verificationFailed,
          'The card could not be verified with its final key',
          cause: error,
        );
      }
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
