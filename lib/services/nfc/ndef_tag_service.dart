import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

import '../../core/crypto/mifare_key.dart';
import '../../core/engine/mifare_write_payload.dart';
import '../../models/card/card.dart';
import '../../models/card/iso14443a.dart';
import '../../models/card/ndef.dart';
import 'mifare_card_writer.dart';

const _madKey = [0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5];
const _ndefKey = [0xd3, 0xf7, 0xd3, 0xf7, 0xd3, 0xf7];
const _defaultKey = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff];

int madCrc(List<int> bytes) {
  var crc = 0xc7;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = ((crc << 1) ^ (crc & 0x80 != 0 ? 0x1d : 0)) & 0xff;
    }
  }
  return crc;
}

int _firstBlock(int sector) =>
    sector < 32 ? sector * 4 : 128 + (sector - 32) * 16;
List<int> _blocks(int sector) =>
    List.generate(sector < 32 ? 3 : 15, (i) => _firstBlock(sector) + i);
int _trailer(int sector) => _firstBlock(sector) + (sector < 32 ? 3 : 15);

Uint8List ndefTlv(Uint8List message) {
  if (message.length > 0xffff) {
    throw const FormatException('NDEF exceeds TLV capacity');
  }
  return Uint8List.fromList([
    3,
    if (message.length < 255)
      message.length
    else ...[
      255,
      message.length >> 8,
      message.length & 255,
    ],
    ...message,
    0xfe,
  ]);
}

Uint8List? readNdefTlv(Uint8List bytes) {
  var offset = 0;
  while (offset < bytes.length) {
    final type = bytes[offset++];
    if (type == 0) continue;
    if (type == 0xfe) return null;
    if (offset == bytes.length) throw const FormatException('Truncated TLV');
    var length = bytes[offset++];
    if (length == 255) {
      if (offset + 2 > bytes.length) {
        throw const FormatException('Truncated TLV length');
      }
      length = (bytes[offset++] << 8) | bytes[offset++];
    }
    if (offset + length > bytes.length) {
      throw const FormatException('Truncated TLV data');
    }
    if (type == 3) return Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
  }
  return null;
}

class NdefTagService {
  final NfcCardChannel channel;
  NdefTagService(this.channel);

  Future<NdefCard?> read(ICCard tag) async {
    Uint8List? message;
    int? capacity;
    if (tag is Iso14443) {
      if (tag.isMifareClassicCandidate) {
        final sectors = await _readMad(tag);
        if (sectors == null) return null;
        final bytes = BytesBuilder();
        for (final sector in sectors) {
          await _auth(tag, sector, MifareCredential(MifareKeyType.a, _ndefKey));
          for (final block in _blocks(sector)) {
            bytes.add(await _readBlock(block));
          }
        }
        capacity = bytes.length;
        message = readNdefTlv(bytes.toBytes());
      } else if (tag.sak == 0) {
        final header = await channel.transceive(Uint8List.fromList([0x30, 0]));
        if (header.length != 16) return null;
        if (header[12] != 0xe1 ||
            header[13] >> 4 != 1 ||
            header[14] == 0 ||
            header[15] >> 4 != 0) {
          return null;
        }
        final bytes = BytesBuilder();
        capacity = header[14] * 8;
        for (var page = 4; bytes.length < capacity; page += 4) {
          bytes.add(await _readPages(page));
        }
        message = readNdefTlv(
          Uint8List.sublistView(bytes.toBytes(), 0, capacity),
        );
      } else if (tag.sak & 0x20 != 0) {
        final result = await _readType4();
        if (result != null) (message, capacity) = result;
      }
    }
    return message == null
        ? null
        : NdefCard(message, physicalCard: tag, capacity: capacity);
  }

  Future<void> write(
    Iso14443 tag,
    NdefCard card, {
    MifareWriteStageCallback? onStage,
    bool Function()? isCancelled,
  }) async {
    onStage?.call(MifareWriteStage.checkingCard);
    void checkCancelled() {
      if (isCancelled?.call() ?? false) {
        _fail(MifareWriteFailure.cancelled, 'Cancelled before writing');
      }
    }

    checkCancelled();
    onStage?.call(MifareWriteStage.checkingPermissions);
    if (tag.isMifareClassicCandidate) {
      await _writeClassic(tag, card.message, onStage, checkCancelled);
    } else if (tag.sak == 0 && tag.id.length == 7) {
      await _writeNtag(card.message, onStage, checkCancelled);
    } else {
      _fail(
        MifareWriteFailure.unsupportedCard,
        'NDEF writing requires NTAG21x or MIFARE Classic',
      );
    }
    onStage?.call(MifareWriteStage.verifying);
    final actual = await read(tag);
    if (actual == null || !listEquals(actual.message, card.message)) {
      _fail(MifareWriteFailure.verificationFailed, 'NDEF read-back mismatch');
    }
  }

  Future<void> _auth(Iso14443 tag, int sector, MifareCredential credential) =>
      channel.authenticateMifare(
        uid: tag.id,
        block: _firstBlock(sector),
        keyA: credential.type == MifareKeyType.a ? credential.value : null,
        keyB: credential.type == MifareKeyType.b ? credential.value : null,
      );

  Future<Uint8List> _readBlock(int block) async {
    final bytes = await channel.readMifareBlock(block);
    if (bytes.length != 16) {
      throw const FormatException('Incomplete MIFARE block');
    }
    return bytes;
  }

  Future<List<int>?> _readMad(Iso14443 tag) async {
    if (tag.sak != 0x08 && tag.sak != 0x18) return null;
    try {
      await channel.reconnect();
      await _auth(tag, 0, MifareCredential(MifareKeyType.a, _madKey));
    } on NfcException catch (error) {
      if (error.type != NfcErrorType.authFailed) rethrow;
      await channel.reconnect();
      return null;
    }
    final trailer = await _readBlock(3);
    final version = trailer[9] & 3;
    if (trailer[9] & 0x80 == 0 || (version != 1 && version != 2)) return null;
    final directory = Uint8List.fromList([
      ...await _readBlock(1),
      ...await _readBlock(2),
    ]);
    final sectors = <int>[];
    void addDirectory(Uint8List data, int firstSector) {
      if (madCrc(data.sublist(1)) != data[0]) {
        throw const FormatException('Invalid MAD checksum');
      }
      for (var offset = 2; offset < data.length; offset += 2) {
        if (data[offset] == 3 && data[offset + 1] == 0xe1) {
          sectors.add(firstSector + (offset - 2) ~/ 2);
        }
      }
    }

    addDirectory(directory, 1);
    if (version == 2) {
      if (tag.sak != 0x18) throw const FormatException('MAD2 on non-4K card');
      await _auth(tag, 16, MifareCredential(MifareKeyType.a, _madKey));
      addDirectory(
        Uint8List.fromList([
          ...await _readBlock(64),
          ...await _readBlock(65),
          ...await _readBlock(66),
        ]),
        17,
      );
    }
    return sectors.isEmpty ? null : sectors;
  }

  Future<MifareCredential> _manager(
    Iso14443 tag,
    int sector, {
    required bool format,
  }) async {
    final candidates = [
      for (final key in [_defaultKey, _madKey, _ndefKey, banaKey, aimeKey])
        for (final type in MifareKeyType.values) MifareCredential(type, key),
    ];
    var authenticated = false;
    for (var i = 0; i < candidates.length; i++) {
      final credential = candidates[i];
      try {
        await channel.reconnect();
        await _auth(tag, sector, credential);
        authenticated = true;
        final trailer = await _readBlock(_trailer(sector));
        final access = MifareSectorAccess.decode(trailer);
        if (!format && (trailer[9] & 0x0f != 0 || trailer[9] >> 6 != 1)) {
          _fail(
            MifareWriteFailure.permissionDenied,
            'NDEF sector $sector is read-only or has an unsupported mapping',
          );
        }
        if (access.trailerPermissions.canReadKeyB(credential.type)) {
          final key = trailer.sublist(10);
          if (!candidates.any(
            (c) => c.type == MifareKeyType.b && listEquals(c.value, key),
          )) {
            candidates.add(MifareCredential(MifareKeyType.b, key));
          }
        }
        final groups = sector == 0 ? [1, 2] : [0, 1, 2];
        if (groups.every(
              (group) =>
                  access
                      .permissionsForBlock(group)
                      .allows(credential.type, MifareDataOperation.write) &&
                  access
                      .permissionsForBlock(group)
                      .allows(credential.type, MifareDataOperation.read),
            ) &&
            (!format ||
                access.trailerPermissions.canWriteEntireTrailer(
                  credential.type,
                ))) {
          return credential;
        }
      } on MifareAccessFormatException {
        _fail(
          MifareWriteFailure.invalidAccessBits,
          'Invalid access bits in sector $sector',
        );
      } on NfcException catch (error) {
        if (error.type != NfcErrorType.authFailed) rethrow;
      }
    }
    _fail(
      authenticated
          ? MifareWriteFailure.permissionDenied
          : MifareWriteFailure.authenticationFailed,
      'Sector $sector is locked or has an unknown key',
    );
  }

  Future<void> _writeClassic(
    Iso14443 tag,
    Uint8List message,
    MifareWriteStageCallback? onStage,
    void Function() checkCancelled,
  ) async {
    if ((tag.sak != 8 && tag.sak != 0x18) ||
        (tag.id.length != 4 && tag.id.length != 7)) {
      _fail(MifareWriteFailure.unsupportedCard, 'Unsupported Classic geometry');
    }
    final existing = await _readMad(tag);
    final format = existing == null;
    final sectors =
        existing ??
        [
          for (var s = 1; s < (tag.sak == 8 ? 16 : 40); s++)
            if (s != 16) s,
        ];
    final dataBlocks = sectors.expand(_blocks).toList();
    final tlv = ndefTlv(message);
    if (tlv.length > dataBlocks.length * 16) {
      _fail(MifareWriteFailure.capacityExceeded, 'NDEF exceeds card capacity');
    }
    final managers = <int, MifareCredential>{};
    final affected = [
      if (format) 0,
      ...sectors,
      if (format && tag.sak == 0x18) 16,
    ];
    for (final sector in affected) {
      checkCancelled();
      managers[sector] = await _manager(tag, sector, format: format);
    }
    checkCancelled();
    onStage?.call(MifareWriteStage.writingData);
    final padded = Uint8List(dataBlocks.length * 16)
      ..setRange(0, tlv.length, tlv);
    // Publish length last: an interrupted write must not advertise partial data.
    final invalid = Uint8List(16)..[0] = 3;
    await _auth(tag, sectors.first, managers[sectors.first]!);
    await _writeBlock(dataBlocks.first, invalid);
    for (final sector in sectors) {
      await _auth(tag, sector, managers[sector]!);
      for (final block in _blocks(sector)) {
        if (block == dataBlocks.first) continue;
        final offset = dataBlocks.indexOf(block) * 16;
        await _writeBlock(
          block,
          Uint8List.sublistView(padded, offset, offset + 16),
        );
      }
    }
    if (format) {
      for (final sector in sectors) {
        await _auth(tag, sector, managers[sector]!);
        await _writeClassicTrailer(tag, sector, _ndefKey, 0x40);
      }
      for (final sector in [0, if (tag.sak == 0x18) 16]) {
        await _auth(tag, sector, managers[sector]!);
        final mad = Uint8List(sector == 0 ? 32 : 48);
        for (var i = 2; i < mad.length; i += 2) {
          mad[i] = 3;
          mad[i + 1] = 0xe1;
        }
        mad[0] = madCrc(mad.sublist(1));
        final blocks = sector == 0 ? [1, 2] : [64, 65, 66];
        for (var i = 0; i < blocks.length; i++) {
          await _writeBlock(
            blocks[i],
            Uint8List.sublistView(mad, i * 16, i * 16 + 16),
          );
        }
        await _writeClassicTrailer(
          tag,
          sector,
          _madKey,
          sector == 0 ? (tag.sak == 8 ? 0xc1 : 0xc2) : 0,
        );
      }
    }
    await _auth(
      tag,
      sectors.first,
      format
          ? MifareCredential(MifareKeyType.b, _defaultKey)
          : managers[sectors.first]!,
    );
    await _writeBlock(dataBlocks.first, Uint8List.sublistView(padded, 0, 16));
  }

  Future<void> _writeClassicTrailer(
    Iso14443 tag,
    int sector,
    List<int> keyA,
    int gpb,
  ) async {
    final dataCondition = MifareAccessCondition.fromValue(
      sector == 0 || sector == 16 ? 4 : 0,
    );
    final access = MifareSectorAccess(
      block0: dataCondition,
      block1: dataCondition,
      block2: dataCondition,
      trailer: MifareAccessCondition.fromValue(3),
      gpb: gpb,
    );
    await channel.writeMifareBlock(
      _trailer(sector),
      Uint8List.fromList([...keyA, ...access.encode(), ..._defaultKey]),
    );
    await channel.reconnect();
    await _auth(tag, sector, MifareCredential(MifareKeyType.b, _defaultKey));
    if (MifareSectorAccess.decode(await _readBlock(_trailer(sector))) !=
        access) {
      _fail(
        MifareWriteFailure.verificationFailed,
        'Trailer verification failed',
      );
    }
    await _auth(tag, sector, MifareCredential(MifareKeyType.a, keyA));
  }

  Future<void> _writeBlock(int block, Uint8List bytes) async {
    await channel.writeMifareBlock(block, bytes);
    if (!listEquals(await _readBlock(block), bytes)) {
      _fail(MifareWriteFailure.verificationFailed, 'Block $block mismatch');
    }
  }

  Future<Uint8List> _readPages(int page) async {
    final bytes = await channel.transceive(Uint8List.fromList([0x30, page]));
    if (bytes.length != 16) {
      throw const FormatException('Incomplete Type 2 READ');
    }
    return bytes;
  }

  Future<void> _writeNtag(
    Uint8List message,
    MifareWriteStageCallback? onStage,
    void Function() checkCancelled,
  ) async {
    final version = await channel.transceive(Uint8List.fromList([0x60]));
    if (version.length != 8 ||
        version[1] != 4 ||
        version[2] != 4 ||
        version[3] != 2 ||
        version[4] != 1 ||
        version[5] != 0 ||
        version[7] != 3) {
      _fail(MifareWriteFailure.unsupportedCard, 'Unrecognized NTAG21x model');
    }
    final (capacity, dynamicPage) = switch (version[6]) {
      0x0f => (144, 0x28),
      0x11 => (504, 0x82),
      0x13 => (888, 0xe2),
      _ => throw const MifareCardWriteException(
        MifareWriteFailure.unsupportedCard,
        'Unsupported NTAG size',
      ),
    };
    final header = await _readPages(0);
    final locks = await _readPages(dynamicPage);
    if (header[10] != 0 ||
        header[11] != 0 ||
        locks.take(3).any((b) => b != 0) ||
        locks[7] < dynamicPage ||
        header[12] != 0xe1 ||
        header[13] != 0x10 ||
        header[15] != 0) {
      _fail(
        MifareWriteFailure.permissionDenied,
        'NTAG is locked, password protected or has an unsupported CC',
      );
    }
    final advertisedCapacity = header[14] * 8;
    if (advertisedCapacity > capacity + 8 || advertisedCapacity == 0) {
      _fail(MifareWriteFailure.unsupportedCard, 'Invalid NTAG capacity');
    }
    final tlv = ndefTlv(message);
    final writableCapacity = advertisedCapacity < capacity
        ? advertisedCapacity
        : capacity;
    if (tlv.length > writableCapacity) {
      _fail(MifareWriteFailure.capacityExceeded, 'NDEF exceeds NTAG capacity');
    }
    final current = BytesBuilder();
    for (var page = 4; current.length < capacity; page += 4) {
      current.add(await _readPages(page));
    }
    // Do not overwrite memory-control / lock-control TLVs from other layouts.
    final old = current.toBytes();
    var first = 0;
    while (first < capacity && old[first] == 0) {
      first++;
    }
    if (first < capacity && old[first] != 3 && old[first] != 0xfe) {
      _fail(
        MifareWriteFailure.unsupportedCard,
        'NTAG contains reserved-memory TLVs',
      );
    }
    checkCancelled();
    onStage?.call(MifareWriteStage.writingData);
    final padded = Uint8List((tlv.length + 3) ~/ 4 * 4)
      ..setRange(0, tlv.length, tlv);
    await _writePage(4, Uint8List.fromList([3, 0, 0xfe, 0]));
    for (var offset = 4; offset < padded.length; offset += 4) {
      await _writePage(
        4 + offset ~/ 4,
        Uint8List.sublistView(padded, offset, offset + 4),
      );
    }
    await _writePage(4, Uint8List.sublistView(padded, 0, 4));
  }

  Future<void> _writePage(int page, Uint8List bytes) async {
    final ack = await channel.transceive(
      Uint8List.fromList([0xa2, page, ...bytes]),
    );
    // PN532 may consume the four-bit ACK; the read-back is authoritative.
    if (ack.isNotEmpty && (ack.length != 1 || ack[0] != 0x0a)) {
      _fail(MifareWriteFailure.writeFailed, 'NTAG rejected WRITE');
    }
    if (!listEquals((await _readPages(page)).sublist(0, 4), bytes)) {
      _fail(MifareWriteFailure.verificationFailed, 'Page $page mismatch');
    }
  }

  Future<(Uint8List, int)?> _readType4() async {
    Future<Uint8List?> apdu(List<int> command) async {
      final res = await channel.transceive(Uint8List.fromList(command));
      if (res.length < 2 || res[res.length - 2] != 0x90 || res.last != 0) {
        return null;
      }
      return Uint8List.sublistView(res, 0, res.length - 2);
    }

    if (await apdu([0, 0xa4, 4, 0, 7, 0xd2, 0x76, 0, 0, 0x85, 1, 1, 0]) ==
        null) {
      return null;
    }
    if (await apdu([0, 0xa4, 0, 0x0c, 2, 0xe1, 3]) == null) return null;
    final cc = await apdu([0, 0xb0, 0, 0, 15]);
    if (cc == null ||
        cc.length < 15 ||
        cc[2] >> 4 > 2 ||
        cc[7] != 4 ||
        cc[8] != 6 ||
        cc[13] != 0) {
      return null;
    }
    if (await apdu([0, 0xa4, 0, 0x0c, 2, cc[9], cc[10]]) == null) return null;
    final size = await apdu([0, 0xb0, 0, 0, 2]);
    if (size == null || size.length != 2) {
      throw const FormatException('Missing NLEN');
    }
    final length = (size[0] << 8) | size[1];
    if (length + 2 > (cc[11] << 8) + cc[12]) {
      throw const FormatException('Invalid NLEN');
    }
    final bytes = BytesBuilder();
    final maxRead = ((cc[3] << 8) | cc[4]).clamp(1, 128);
    while (bytes.length < length) {
      final offset = bytes.length + 2;
      final count = (length - bytes.length).clamp(1, maxRead);
      final part = await apdu([0, 0xb0, offset >> 8, offset & 255, count]);
      if (part == null || part.length != count) {
        throw const FormatException('Incomplete NDEF file');
      }
      bytes.add(part);
    }
    return (bytes.toBytes(), ((cc[11] << 8) | cc[12]) - 2);
  }

  Never _fail(MifareWriteFailure failure, String message) =>
      throw MifareCardWriteException(failure, message);
}
