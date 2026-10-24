import 'dart:math';

import 'package:flutter/foundation.dart';

/// A read-only NFC Forum Type 4 tag (mapping 2.0) serving one NDEF message.
///
/// Answers the C-APDUs a phone sends after ISO-DEP activation.
class Type4NdefTag {
  /// Largest message whose file, with its two-byte NLEN, keeps `READ BINARY`
  /// offsets below 0x8000, where P1 would mean a short EF identifier.
  static const maxMessageSize = 0x7FFE;

  /// MLe for a PN532 bridged by CDC: 53 data bytes plus the status word.
  static const maxReadLength = 53;

  static const _aid = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01];

  final int maxRead;
  final Uint8List ndefFile;
  final Uint8List capabilityContainer;

  bool _applicationSelected = false;
  Uint8List? _selected;
  bool _messageRead = false;

  Type4NdefTag(Uint8List message, {this.maxRead = maxReadLength})
    : ndefFile = Uint8List.fromList([
        message.length >> 8,
        message.length & 0xFF,
        ...message,
      ]),
      capabilityContainer = Uint8List.fromList([
        0x00, 0x0F, // CCLEN
        0x20, // mapping version 2.0
        0x00, maxRead, // MLe
        0x00, maxRead, // MLc
        0x04, 0x06, // NDEF file control TLV
        0xE1, 0x04, // NDEF file identifier
        (message.length + 2) >> 8, (message.length + 2) & 0xFF,
        0x00, // read access granted
        0xFF, // no write access
      ]) {
    if (message.isEmpty || message.length > maxMessageSize) {
      throw ArgumentError.value(
        message.length,
        'message.length',
        'Must be 1–$maxMessageSize bytes',
      );
    }
    if (maxRead < 1 || maxRead > maxReadLength) {
      throw RangeError.range(maxRead, 1, maxReadLength, 'maxRead');
    }
  }

  /// Forgets the selection, as a newly activated session starts unselected.
  void reset() {
    _applicationSelected = false;
    _selected = null;
    _messageRead = false;
  }

  /// Whether the last end of the NDEF file was read since the previous call.
  bool takeMessageRead() {
    final read = _messageRead;
    _messageRead = false;
    return read;
  }

  Uint8List process(Uint8List apdu) {
    if (apdu.length < 4) return _sw(0x67, 0x00);
    if (apdu[0] != 0x00) return _sw(0x6E, 0x00);
    if (apdu[1] == 0xD6) return _sw(0x69, 0x82);
    if (apdu[1] == 0xA4) return _select(apdu);
    if (apdu[1] != 0xB0) return _sw(0x6D, 0x00);
    if (apdu.length != 5) return _sw(0x67, 0x00);
    final selected = _selected;
    if (!_applicationSelected || selected == null) return _sw(0x69, 0x86);
    // Only offset addressing is supported, not a short EF identifier in P1.
    if (apdu[2] & 0x80 != 0) return _sw(0x6B, 0x00);
    final offset = apdu[2] << 8 | apdu[3];
    if (offset >= selected.length) return _sw(0x6B, 0x00);
    final requested = apdu[4] == 0 ? 256 : apdu[4];
    final end =
        offset + min<int>(requested, min(maxRead, selected.length - offset));
    if (identical(selected, ndefFile) && end == selected.length) {
      _messageRead = true;
    }
    return Uint8List.fromList([...selected.sublist(offset, end), 0x90, 0x00]);
  }

  Uint8List _select(Uint8List apdu) {
    if (apdu.length < 5 ||
        (apdu.length != 5 + apdu[4] && apdu.length != 6 + apdu[4])) {
      return _sw(0x67, 0x00);
    }
    final data = apdu.sublist(5, 5 + apdu[4]);
    if (apdu[2] == 0x04) {
      if (apdu[3] != 0x00 && apdu[3] != 0x0C) return _sw(0x6A, 0x86);
      if (!listEquals(data, _aid)) return _sw(0x6A, 0x82);
      _applicationSelected = true;
      _selected = null;
      return _sw(0x90, 0x00);
    }
    if (apdu[2] != 0x00 || (apdu[3] != 0x00 && apdu[3] != 0x0C)) {
      return _sw(0x6A, 0x86);
    }
    if (!_applicationSelected) return _sw(0x69, 0x86);
    if (listEquals(data, [0xE1, 0x03])) {
      _selected = capabilityContainer;
    } else if (listEquals(data, [0xE1, 0x04])) {
      _selected = ndefFile;
    } else {
      return _sw(0x6A, 0x82);
    }
    return _sw(0x90, 0x00);
  }

  static Uint8List _sw(int sw1, int sw2) => Uint8List.fromList([sw1, sw2]);
}
