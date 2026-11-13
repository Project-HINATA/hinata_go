import 'dart:typed_data';

/// The MIFARE Classic stream cipher, in the odd/even register form that
/// crapto1 uses.
class Crypto1 {
  static const _polyOdd = 0x29CE5C;
  static const _polyEven = 0x870804;
  static const _mask24 = 0xFFFFFF;

  int _odd = 0;
  int _even = 0;

  Crypto1._();

  /// Loads a 48-bit [key], most significant byte first as stored in a
  /// sector trailer.
  Crypto1(int key) {
    for (var i = 47; i > 0; i -= 2) {
      _odd = (_odd << 1 | _bit(key, (i - 1) ^ 7)) & _mask24;
      _even = (_even << 1 | _bit(key, i ^ 7)) & _mask24;
    }
  }

  /// Loads a key given as its six bytes.
  factory Crypto1.fromBytes(List<int> key) {
    if (key.length != 6) {
      throw ArgumentError.value(key.length, 'key.length', 'Must be 6');
    }
    final crypto = Crypto1._();
    for (final byte in key) {
      for (var bit = 0; bit < 8; bit += 2) {
        crypto._odd = (crypto._odd << 1 | _bit(byte, bit + 1)) & _mask24;
        crypto._even = (crypto._even << 1 | _bit(byte, bit)) & _mask24;
      }
    }
    return crypto;
  }

  /// The keystream bit the next clock gives, without clocking.
  int peek() => _filter(_odd);

  /// Clocks once, shifting in [input], and returns the keystream bit. With
  /// [encrypted] the input is ciphertext and is decrypted as it goes in.
  int bit([int input = 0, bool encrypted = false]) {
    final out = _filter(_odd);
    var feedIn = encrypted ? out : 0;
    feedIn ^= input & 1;
    feedIn ^= _polyOdd & _odd;
    feedIn ^= _polyEven & _even;
    _even = (_even << 1 | _parity32(feedIn)) & _mask24;
    final t = _odd;
    _odd = _even;
    _even = t;
    return out;
  }

  /// Eight clocks, least significant bit first.
  int byte([int input = 0, bool encrypted = false]) {
    var out = 0;
    for (var i = 0; i < 8; i++) {
      out |= bit(input >> i, encrypted) << i;
    }
    return out;
  }

  /// 32 clocks over a word sent most significant byte first, each byte
  /// least significant bit first.
  int word([int input = 0, bool encrypted = false]) {
    var out = 0;
    for (var i = 0; i < 32; i++) {
      out |= bit(input >> (i ^ 24), encrypted) << (i ^ 24);
    }
    return out;
  }

  static int _bit(int x, int n) => (x >> n) & 1;

  static int _parity32(int x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    return (0x6996 >> (x & 0xF)) & 1;
  }

  static int _filter(int x) {
    var f = (0xF22C0 >> (x & 0xF)) & 16;
    f |= (0x6C9C0 >> (x >> 4 & 0xF)) & 8;
    f |= (0x3C8B0 >> (x >> 8 & 0xF)) & 4;
    f |= (0x1E458 >> (x >> 12 & 0xF)) & 2;
    f |= (0x0D938 >> (x >> 16 & 0xF)) & 1;
    return (0xEC57E80A >> f) & 1;
  }
}

/// The card's nonce generator advanced [n] steps from [x].
int prngSuccessor(int x, int n) {
  x = _swap32(x);
  while (n-- > 0) {
    x =
        (x >> 1 | ((x >> 16 ^ x >> 18 ^ x >> 19 ^ x >> 21) & 1) << 31) &
        0xFFFFFFFF;
  }
  return _swap32(x);
}

int _swap32(int x) =>
    (x & 0xFF) << 24 | (x & 0xFF00) << 8 | (x >> 8) & 0xFF00 | (x >> 24) & 0xFF;

/// The odd parity bit of [byte].
int oddParity8(int byte) {
  var x = byte & 0xFF;
  x ^= x >> 4;
  return 1 ^ ((0x6996 >> (x & 0xF)) & 1);
}

/// ISO/IEC 14443-3 Type A CRC, low byte first.
Uint8List crcA(List<int> data) {
  var crc = 0x6363;
  for (var b in data) {
    b ^= crc & 0xFF;
    b = (b ^ (b << 4)) & 0xFF;
    crc = (crc >> 8) ^ (b << 8) ^ (b << 3) ^ (b >> 4);
  }
  return Uint8List.fromList([crc & 0xFF, (crc >> 8) & 0xFF]);
}

/// Packs [data] with one parity bit after each byte, least significant data
/// bit first, returning the packed bytes and `TxLastBits` (0 when the last
/// byte is full).
(Uint8List, int) packParity(List<int> data, List<int> parities) {
  if (data.length != parities.length) {
    throw ArgumentError('data and parities must have the same length');
  }
  final totalBits = data.length * 9;
  final out = Uint8List((totalBits + 7) >> 3);
  var bitIndex = 0;
  for (var i = 0; i < data.length; i++) {
    final byte = data[i];
    for (var b = 0; b < 8; b++) {
      if ((byte >> b) & 1 != 0) {
        out[bitIndex >> 3] |= 1 << (bitIndex & 7);
      }
      bitIndex++;
    }
    if (parities[i] & 1 != 0) {
      out[bitIndex >> 3] |= 1 << (bitIndex & 7);
    }
    bitIndex++;
  }
  return (out, totalBits & 7);
}

/// Unpacks up to [byteCount] 9-bit (8 data bits + 1 parity bit) characters
/// from [raw].
(Uint8List, Uint8List) unpackParity(List<int> raw, int byteCount) {
  final available = (raw.length * 8) ~/ 9;
  final count = byteCount < available ? byteCount : available;
  final data = Uint8List(count);
  final parities = Uint8List(count);
  for (var k = 0; k < count; k++) {
    final base = k * 9;
    var byte = 0;
    for (var i = 0; i < 8; i++) {
      final bitPos = base + i;
      byte |= ((raw[bitPos >> 3] >> (bitPos & 7)) & 1) << i;
    }
    final parityPos = base + 8;
    data[k] = byte;
    parities[k] = (raw[parityPos >> 3] >> (parityPos & 7)) & 1;
  }
  return (data, parities);
}
