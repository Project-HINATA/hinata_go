import 'dart:typed_data';

enum MifareKeyType { a, b }

enum MifareDataOperation { read, write, increment, decrementTransferRestore }

class MifareAccessFormatException implements Exception {
  final String message;

  const MifareAccessFormatException(this.message);

  @override
  String toString() => 'MifareAccessFormatException: $message';
}

class MifareAccessCondition {
  final int value;

  const MifareAccessCondition._(this.value);

  const MifareAccessCondition.fromBits({
    required bool c1,
    required bool c2,
    required bool c3,
  }) : value = (c1 ? 4 : 0) | (c2 ? 2 : 0) | (c3 ? 1 : 0);

  factory MifareAccessCondition.fromValue(int value) {
    if (value < 0 || value > 7) {
      throw RangeError.range(value, 0, 7, 'value');
    }
    return MifareAccessCondition._(value);
  }

  bool get c1 => (value & 4) != 0;
  bool get c2 => (value & 2) != 0;
  bool get c3 => (value & 1) != 0;

  @override
  bool operator ==(Object other) =>
      other is MifareAccessCondition && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toRadixString(2).padLeft(3, '0');
}

class MifareDataBlockPermissions {
  final MifareAccessCondition condition;
  final bool keyBMayAuthenticate;

  const MifareDataBlockPermissions({
    required this.condition,
    required this.keyBMayAuthenticate,
  });

  bool allows(MifareKeyType key, MifareDataOperation operation) {
    if (key == MifareKeyType.b && !keyBMayAuthenticate) return false;

    final isA = key == MifareKeyType.a;
    return switch ((condition.value, operation)) {
      (0, _) => true,
      (2, MifareDataOperation.read) => true,
      (4, MifareDataOperation.read) => true,
      (4, MifareDataOperation.write) => !isA,
      (6, MifareDataOperation.read) => true,
      (6, MifareDataOperation.write) => !isA,
      (6, MifareDataOperation.increment) => !isA,
      (6, MifareDataOperation.decrementTransferRestore) => true,
      (1, MifareDataOperation.read) => true,
      (1, MifareDataOperation.decrementTransferRestore) => true,
      (3, MifareDataOperation.read) => !isA,
      (3, MifareDataOperation.write) => !isA,
      (5, MifareDataOperation.read) => !isA,
      _ => false,
    };
  }
}

class MifareTrailerPermissions {
  final MifareAccessCondition condition;

  const MifareTrailerPermissions(this.condition);

  bool get keyBMayAuthenticate => switch (condition.value) {
    0 || 1 || 2 => false,
    _ => true,
  };

  bool canReadKeyA(MifareKeyType _) => false;

  bool canReadAccessBits(MifareKeyType key) => switch (condition.value) {
    0 || 1 || 2 => key == MifareKeyType.a,
    _ => true,
  };

  bool canWriteKeyA(MifareKeyType key) => switch (condition.value) {
    0 || 1 => key == MifareKeyType.a,
    3 || 4 => key == MifareKeyType.b,
    _ => false,
  };

  bool canWriteAccessBits(MifareKeyType key) => switch (condition.value) {
    1 => key == MifareKeyType.a,
    3 || 5 => key == MifareKeyType.b,
    _ => false,
  };

  bool canReadKeyB(MifareKeyType key) =>
      !keyBMayAuthenticate && key == MifareKeyType.a;

  bool canWriteKeyB(MifareKeyType key) => switch (condition.value) {
    0 || 1 => key == MifareKeyType.a,
    3 || 4 => key == MifareKeyType.b,
    _ => false,
  };

  bool canWriteEntireTrailer(MifareKeyType key) =>
      canWriteKeyA(key) && canWriteAccessBits(key) && canWriteKeyB(key);
}

class MifareSectorAccess {
  final MifareAccessCondition block0;
  final MifareAccessCondition block1;
  final MifareAccessCondition block2;
  final MifareAccessCondition trailer;
  final int gpb;

  const MifareSectorAccess({
    required this.block0,
    required this.block1,
    required this.block2,
    required this.trailer,
    this.gpb = 0x69,
  });

  factory MifareSectorAccess.decode(Uint8List bytes) {
    if (bytes.length != 3 && bytes.length != 4 && bytes.length != 16) {
      throw MifareAccessFormatException(
        'Expected 3 access bytes, 4 access/GPB bytes, or a 16-byte trailer',
      );
    }

    final offset = bytes.length == 16 ? 6 : 0;
    final byte6 = bytes[offset];
    final byte7 = bytes[offset + 1];
    final byte8 = bytes[offset + 2];
    final gpb = bytes.length == 3 ? 0x69 : bytes[offset + 3];

    final c1 = (byte7 >> 4) & 0x0f;
    final c2 = byte8 & 0x0f;
    final c3 = (byte8 >> 4) & 0x0f;
    final invertedC1 = byte6 & 0x0f;
    final invertedC2 = (byte6 >> 4) & 0x0f;
    final invertedC3 = byte7 & 0x0f;

    if ((c1 ^ invertedC1) != 0x0f ||
        (c2 ^ invertedC2) != 0x0f ||
        (c3 ^ invertedC3) != 0x0f) {
      throw const MifareAccessFormatException(
        'Access-bit inverted copies do not match',
      );
    }

    MifareAccessCondition conditionAt(int block) {
      return MifareAccessCondition.fromBits(
        c1: (c1 & (1 << block)) != 0,
        c2: (c2 & (1 << block)) != 0,
        c3: (c3 & (1 << block)) != 0,
      );
    }

    return MifareSectorAccess(
      block0: conditionAt(0),
      block1: conditionAt(1),
      block2: conditionAt(2),
      trailer: conditionAt(3),
      gpb: gpb,
    );
  }

  Uint8List encode() {
    if (gpb < 0 || gpb > 0xff) {
      throw RangeError.range(gpb, 0, 0xff, 'gpb');
    }

    final conditions = [block0, block1, block2, trailer];
    var c1 = 0;
    var c2 = 0;
    var c3 = 0;
    for (var block = 0; block < conditions.length; block++) {
      final condition = conditions[block];
      if (condition.c1) c1 |= 1 << block;
      if (condition.c2) c2 |= 1 << block;
      if (condition.c3) c3 |= 1 << block;
    }

    final encoded = Uint8List.fromList([
      ((~c2 & 0x0f) << 4) | (~c1 & 0x0f),
      ((c1 & 0x0f) << 4) | (~c3 & 0x0f),
      ((c3 & 0x0f) << 4) | (c2 & 0x0f),
      gpb,
    ]);

    final decoded = MifareSectorAccess.decode(encoded);
    if (decoded != this) {
      throw const MifareAccessFormatException(
        'Encoded access bits failed round-trip validation',
      );
    }
    return encoded;
  }

  MifareDataBlockPermissions permissionsForBlock(int block) {
    final condition = switch (block) {
      0 => block0,
      1 => block1,
      2 => block2,
      _ => throw RangeError.range(block, 0, 2, 'block'),
    };
    return MifareDataBlockPermissions(
      condition: condition,
      keyBMayAuthenticate: trailerPermissions.keyBMayAuthenticate,
    );
  }

  MifareTrailerPermissions get trailerPermissions =>
      MifareTrailerPermissions(trailer);

  @override
  bool operator ==(Object other) =>
      other is MifareSectorAccess &&
      other.block0 == block0 &&
      other.block1 == block1 &&
      other.block2 == block2 &&
      other.trailer == trailer &&
      other.gpb == gpb;

  @override
  int get hashCode => Object.hash(block0, block1, block2, trailer, gpb);
}
