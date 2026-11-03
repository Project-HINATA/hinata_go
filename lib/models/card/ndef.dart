import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ndef/ndef.dart' as ndef;

import 'card.dart';
import 'felica.dart';
import 'iso14443a.dart';
import 'iso15693.dart';

/// Keeps the original message, including unknown records and identifiers.
class NdefCard extends CardData {
  final Uint8List message;
  final int? capacity;

  NdefCard(
    Uint8List message, {
    List<CardTag> tags = const [],
    super.physicalCard,
    this.capacity,
  }) : message = Uint8List.fromList(message).asUnmodifiableView(),
       super(
         tags: {
           CardTag.ndef,
           ...tags,
           ...?physicalCard?.tags,
           if (physicalCard is Felica) CardTag.felica,
           if (physicalCard is Iso15693) CardTag.iso15693,
           if (physicalCard is Iso14443)
             physicalCard.isMifareClassicCandidate
                 ? CardTag.mifareClassic
                 : CardTag.iso14443a,
         }.toList(),
       ) {
    if (capacity != null && capacity! < 0) {
      throw const FormatException('Invalid NDEF tag metadata');
    }
    decodeNdef(message);
  }

  factory NdefCard.fromRecords(List<ndef.NDEFRecord> records) =>
      NdefCard(ndef.encodeNdefMessage(records));

  List<ndef.NDEFRecord> get records => decodeNdef(message);

  @override
  String get type => 'ndef';
  @override
  String get name => physicalCard?.name ?? 'NDEF';
  @override
  String get showedValue => records.map(ndefRecordValue).join('\n');
  @override
  bool isSameCard(ICCard other) =>
      other is NdefCard &&
      hasPhysicalCard == other.hasPhysicalCard &&
      idString == other.idString &&
      listEquals(message, other.message);
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'message': base64Encode(message),
    if (capacity != null) 'capacity': capacity,
  };

  factory NdefCard.fromJson(Map<String, dynamic> json) {
    return NdefCard(
      base64Decode(json['message'] as String),
      physicalCard: CardData.readPhysicalCard(json),
      capacity: json['capacity'] as int?,
      tags:
          (json['tags'] as List<dynamic>?)?.map(CardTag.fromJson).toList() ??
          [],
    );
  }

  Uri? get prismUrl {
    for (final record in records) {
      final url = _prismUrl(record, 0);
      if (url != null) return url;
    }
    return null;
  }
}

/// The NDEF [card] carries: an NDEF card itself, or the message a FeliCa
/// card holds as a Type 3 tag, with the card's identity as its physical
/// card. Null when it carries none, or a message that does not decode.
NdefCard? ndefOf(ICCard card) {
  if (card is NdefCard) return card;
  if (card is! Felica) return null;
  final message = card.ndefMessage;
  if (message == null) return null;
  try {
    return NdefCard(
      message,
      physicalCard: Felica(card.id, card.pmm, card.systemCode),
    );
  } on FormatException {
    return null;
  }
}

Uri? _prismUrl(ndef.NDEFRecord record, int depth) {
  final uri = ndefRecordUri(record);
  if (uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const {'link.neri.moe', 'link-beta.neri.moe'}.contains(uri.host)) {
    return uri;
  }
  if (depth < 4 &&
      record.tnf == ndef.TypeNameFormat.nfcWellKnown &&
      listEquals(record.type, [0x53, 0x70])) {
    try {
      for (final nested in decodeNdef(record.payload!)) {
        final url = _prismUrl(nested, depth + 1);
        if (url != null) return url;
      }
    } on FormatException {
      return null;
    }
  }
  return null;
}

Uri? ndefRecordUri(ndef.NDEFRecord record) {
  try {
    if (record.tnf == ndef.TypeNameFormat.absoluteURI) {
      return Uri.tryParse(utf8.decode(record.type!));
    }
    if (record.tnf == ndef.TypeNameFormat.nfcWellKnown &&
        listEquals(record.type, [0x55])) {
      final payload = record.payload!;
      if (payload.isEmpty || payload[0] >= ndef.UriRecord.prefixMap.length) {
        return null;
      }
      return Uri.tryParse(
        ndef.UriRecord.prefixMap[payload[0]] + utf8.decode(payload.sublist(1)),
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

String ndefRecordValue(ndef.NDEFRecord record) {
  final uri = ndefRecordUri(record);
  if (uri != null) return uri.toString();
  try {
    final decoded = ndef.NDEFRecord.doDecode(
      record.tnf,
      record.type!,
      record.payload!,
      id: record.id,
    );
    if (decoded is ndef.TextRecord) return decoded.text ?? '';
    if (decoded is ndef.WifiRecord) {
      return 'SSID: ${decoded.ssid}\n${decoded.authenticationType.name} / ${decoded.encryptionType.name}';
    }
    if (record.tnf == ndef.TypeNameFormat.media ||
        record.tnf == ndef.TypeNameFormat.nfcExternal) {
      final text = utf8.decode(record.payload!);
      if (!text.runes.any((r) => r < 32 && r != 9 && r != 10 && r != 13)) {
        return text;
      }
    }
  } catch (_) {
    // Opaque and malformed record payloads must still be saved without loss.
  }
  return (record.payload ?? Uint8List(0))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

/// Validate lengths and flags in release builds; reassemble chunked records.
List<ndef.NDEFRecord> decodeNdef(Uint8List data) {
  if (data.isEmpty) return [];
  var offset = 0;
  var ended = false;
  ndef.NDEFRecord? chunk;
  final records = <ndef.NDEFRecord>[];
  int byte() {
    if (offset >= data.length) throw const FormatException('Truncated NDEF');
    return data[offset++];
  }

  Uint8List take(int length) {
    if (length > data.length - offset) {
      throw const FormatException('Truncated NDEF payload');
    }
    final bytes = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return bytes;
  }

  while (offset < data.length) {
    final start = offset;
    final flags = byte();
    final tnf = flags & 7;
    final mb = flags & 0x80 != 0;
    final me = flags & 0x40 != 0;
    final cf = flags & 0x20 != 0;
    final il = flags & 8 != 0;
    if (ended || mb != (start == 0) || (cf && me) || tnf == 7) {
      throw const FormatException('Invalid NDEF flags');
    }
    final typeLength = byte();
    var payloadLength = byte();
    if (flags & 0x10 == 0) {
      for (var i = 0; i < 3; i++) {
        payloadLength = (payloadLength << 8) | byte();
      }
    }
    final idLength = il ? byte() : 0;
    if ((tnf == 0 && (typeLength != 0 || payloadLength != 0 || il || cf)) ||
        ((tnf == 5 || tnf == 6) && typeLength != 0) ||
        (tnf >= 1 && tnf <= 4 && typeLength == 0) ||
        ((chunk != null) != (tnf == 6)) ||
        (tnf == 6 && il)) {
      throw const FormatException('Invalid NDEF record');
    }
    final type = take(typeLength);
    final id = take(idLength);
    final payload = take(payloadLength);
    if (chunk != null) {
      chunk.payload = Uint8List.fromList([...chunk.payload!, ...payload]);
      if (!cf) {
        records.add(chunk);
        chunk = null;
      }
    } else {
      final record = ndef.NDEFRecord(
        tnf: ndef.TypeNameFormat.values[tnf],
        type: type,
        id: id.isEmpty ? null : id,
        payload: payload,
      );
      if (cf) {
        chunk = record;
      } else {
        records.add(record);
      }
    }
    ended = me;
  }
  if (!ended || chunk != null) {
    throw const FormatException('Unterminated NDEF message');
  }
  return records;
}
