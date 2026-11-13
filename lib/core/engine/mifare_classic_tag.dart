import 'dart:math';
import 'dart:typed_data';

import '../crypto/crypto1.dart';

/// A raw parity-packed MIFARE Classic target response for
/// `TgResponseToInitiator` and the `CIU_BitFraming` `TxLastBits` value.
class MifareFrame {
  final Uint8List raw;
  final int lastBits;

  const MifareFrame(this.raw, this.lastBits);
}

/// An emulated MIFARE Classic 1K card, framed with host-computed CRC_A and
/// odd parity bits as required when Crypto1 encrypts parity.
///
/// The PN532 target hardware forces the first byte of NFCID1 to `0x08`, so
/// [uid] must start with `0x08`. Writes are acknowledged when the sector's
/// access bits allow them, and their data is discarded.
class MifareClassicTag {
  static const ack = 0x0A;
  static const nak = 0x04;

  final Uint8List uid;
  final List<Uint8List> blocks;

  /// The block whose read counts as the reader reading the card.
  final int? markerBlock;

  final int Function() _nextNonce;
  final int _uidWord;

  Crypto1? _crypto;
  int? _authSector;
  bool _authKeyB = false;
  int? _pendingAuthNonce;
  int _pendingSector = 0;
  bool _pendingKeyB = false;
  int? _pendingWriteBlock;
  bool _markerRead = false;

  MifareClassicTag({
    required Uint8List uid,
    required List<Uint8List> blocks,
    this.markerBlock,
    int Function()? nextNonce,
  }) : uid = Uint8List.fromList(uid),
       blocks = List.unmodifiable(blocks.map(Uint8List.fromList)),
       _nextNonce = nextNonce ?? _randomNonce,
       _uidWord = _readWord(uid, 0) {
    if (uid.length != 4 || uid[0] != 0x08) {
      throw ArgumentError.value(
        uid,
        'uid',
        'Must be 4 bytes starting with 0x08',
      );
    }
    if (blocks.length != 64 || blocks.any((b) => b.length != 16)) {
      throw ArgumentError('MIFARE Classic 1K requires 64 blocks of 16 bytes');
    }
  }

  /// Resets the authentication and command state between RF activations.
  void reset() {
    _crypto = null;
    _authSector = null;
    _authKeyB = false;
    _pendingAuthNonce = null;
    _pendingSector = 0;
    _pendingKeyB = false;
    _pendingWriteBlock = null;
  }

  /// Whether [markerBlock] was read since the previous call.
  bool takeMarkerRead() {
    final read = _markerRead;
    _markerRead = false;
    return read;
  }

  /// Processes the first command returned by `TgInitAsTarget`, which arrives
  /// in plaintext with its CRC_A stripped by the PN532.
  MifareFrame? first(List<int> command) => _command(command);

  /// Processes a raw 9-bit parity-packed frame from `TgGetInitiatorCommand`.
  MifareFrame? handle(List<int> raw) {
    if (_pendingAuthNonce case final nt?) {
      final (data, _) = unpackParity(raw, 8);
      if (data.length < 8) return null;
      _pendingAuthNonce = null;
      final crypto = _crypto!;
      final nr = _readWord(data, 0);
      var ar = _readWord(data, 4);
      crypto.word(nr, true);
      ar ^= crypto.word();
      if (ar != prngSuccessor(nt, 64)) {
        _crypto = null;
        return null;
      }
      _authSector = _pendingSector;
      _authKeyB = _pendingKeyB;
      return _encrypted(_wordBytes(prngSuccessor(nt, 96)));
    }

    final expectedBytes = _pendingWriteBlock != null ? 18 : 4;
    var (data, _) = unpackParity(raw, expectedBytes);
    if (_crypto case final crypto?) {
      data = Uint8List.fromList([
        for (final byte in data) byte ^ crypto.byte(),
      ]);
    }
    if (data.length < 2) return null;
    final body = Uint8List.sublistView(data, 0, data.length - 2);
    final crc = crcA(body);
    if (data[data.length - 2] != crc[0] || data[data.length - 1] != crc[1]) {
      return null;
    }
    return _command(body);
  }

  MifareFrame? _command(List<int> cmd) {
    if (_pendingWriteBlock case final block?) {
      _pendingWriteBlock = null;
      if (cmd.length != 16 || !_canWrite(block)) {
        return _nibble(nak);
      }
      // Writes are acknowledged and discarded.
      return _nibble(ack);
    }
    if (cmd.isEmpty) return null;
    final op = cmd[0];
    if ((op == 0x60 || op == 0x61) && cmd.length >= 2) {
      final block = cmd[1];
      if (block >= 64) return _nibble(nak);
      final nested = _crypto != null;
      final nt = _nextNonce() & 0xFFFFFFFF;
      final crypto = Crypto1.fromBytes(_key(block, op == 0x61));
      _crypto = crypto;
      _pendingAuthNonce = nt;
      _pendingSector = block ~/ 4;
      _pendingKeyB = op == 0x61;
      final ks = crypto.word(_uidWord ^ nt);
      final ntBytes = _wordBytes(nt);
      if (nested) {
        final enc = _wordBytes(nt ^ ks);
        final ksBytes = _wordBytes(ks);
        final parities = [
          for (var i = 0; i < 4; i++)
            oddParity8(ntBytes[i]) ^
                (i < 3 ? (ksBytes[i + 1] & 1) : crypto.peek()),
        ];
        final (packed, lastBits) = packParity(enc, parities);
        return MifareFrame(packed, lastBits);
      }
      return _plain(ntBytes);
    }

    if (_crypto == null || _authSector == null) return null;

    if (op == 0x30 && cmd.length == 2) {
      final block = cmd[1];
      if (block >= 64 || block ~/ 4 != _authSector || !_mayRead(block)) {
        return _nibble(nak);
      }
      final data = _read(block);
      if (block == markerBlock) _markerRead = true;
      return _encrypted(Uint8List.fromList([...data, ...crcA(data)]));
    }

    if (op == 0xA0 && cmd.length == 2) {
      final block = cmd[1];
      if (block >= 64 ||
          block == 0 ||
          block ~/ 4 != _authSector ||
          !_mayWrite(block)) {
        return _nibble(nak);
      }
      _pendingWriteBlock = block;
      return _nibble(ack);
    }

    if (op == 0x50) {
      return null;
    }

    return _nibble(nak);
  }

  MifareFrame _plain(List<int> data) {
    final (raw, lastBits) = packParity(data, [
      for (final byte in data) oddParity8(byte),
    ]);
    return MifareFrame(raw, lastBits);
  }

  MifareFrame _encrypted(List<int> data) {
    final crypto = _crypto!;
    final out = Uint8List(data.length);
    final parities = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      out[i] = byte ^ crypto.byte();
      parities[i] = oddParity8(byte) ^ crypto.peek();
    }
    final (raw, lastBits) = packParity(out, parities);
    return MifareFrame(raw, lastBits);
  }

  MifareFrame _nibble(int value) {
    if (_crypto case final crypto?) {
      for (var i = 0; i < 4; i++) {
        value ^= crypto.bit() << i;
      }
    }
    return MifareFrame(Uint8List.fromList([value & 0x0F]), 4);
  }

  Uint8List _key(int block, bool keyB) {
    final trailer = blocks[_trailerOf(block)];
    return Uint8List.sublistView(trailer, keyB ? 10 : 0, keyB ? 16 : 6);
  }

  int _accessBits(int block) {
    final trailer = blocks[_trailerOf(block)];
    final n = block & 3;
    final c1 = (trailer[7] >> (4 + n)) & 1;
    final c2 = (trailer[8] >> n) & 1;
    final c3 = (trailer[8] >> (4 + n)) & 1;
    return c1 << 2 | c2 << 1 | c3;
  }

  bool _keyBReadable(int block) {
    final ac = _accessBits(_trailerOf(block));
    return ac == 0x00 || ac == 0x01 || ac == 0x02;
  }

  bool _mayRead(int block) {
    if ((block & 3) == 3) return true;
    if (_authKeyB && _keyBReadable(block)) return false;
    final ac = _accessBits(block);
    return switch (ac) {
      0 || 1 || 2 || 4 || 6 => true,
      3 || 5 => _authKeyB,
      _ => false,
    };
  }

  bool _mayWrite(int block) {
    if ((block & 3) == 3) return true;
    if (_authKeyB && _keyBReadable(block)) return false;
    final ac = _accessBits(block);
    return switch (ac) {
      0 => true,
      3 || 4 || 6 => _authKeyB,
      _ => false,
    };
  }

  bool _canWrite(int block) {
    if ((block & 3) != 3) return true;
    final ac = _accessBits(block);
    final keysOk =
        (!_authKeyB && (ac == 0x00 || ac == 0x01)) ||
        (_authKeyB && (ac == 0x04 || ac == 0x03));
    final accOk =
        (!_authKeyB && ac == 0x01) || (_authKeyB && (ac == 0x03 || ac == 0x05));
    return keysOk || accOk;
  }

  Uint8List _read(int block) {
    final data = Uint8List.fromList(blocks[block]);
    if ((block & 3) == 3) {
      data.fillRange(0, 6, 0);
      if (!_keyBReadable(block) || _authKeyB) {
        data.fillRange(10, 16, 0);
      }
    }
    return data;
  }

  static int _trailerOf(int block) => block | 3;

  static int _readWord(List<int> bytes, int offset) =>
      ((bytes[offset] & 0xFF) << 24 |
          (bytes[offset + 1] & 0xFF) << 16 |
          (bytes[offset + 2] & 0xFF) << 8 |
          (bytes[offset + 3] & 0xFF)) &
      0xFFFFFFFF;

  static Uint8List _wordBytes(int word) => Uint8List.fromList([
    (word >> 24) & 0xFF,
    (word >> 16) & 0xFF,
    (word >> 8) & 0xFF,
    word & 0xFF,
  ]);

  static final _random = Random.secure();

  static int _randomNonce() =>
      (_random.nextInt(0x10000) << 16) | _random.nextInt(0x10000);
}
