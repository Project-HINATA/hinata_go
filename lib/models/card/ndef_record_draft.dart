import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ndef/ndef.dart' as ndef;

import 'ndef.dart';
import 'ndef_presets.dart';

/// The kinds of record the NDEF editor makes, each with a form of its own.
enum NdefRecordKind {
  url,
  text,
  phone,
  email,
  sms,
  location,
  wifi,
  contact,
  androidApp,
  mime,
  external,
  raw;

  /// Kinds that edit the record's type and bytes rather than what it does.
  bool get isAdvanced => index >= mime.index;

  /// The fields of this kind's form, in the order they are shown.
  List<NdefField> get fields => switch (this) {
    url => const [NdefField.url],
    text => const [NdefField.text, NdefField.language],
    phone => const [NdefField.phone],
    email => const [NdefField.email, NdefField.subject, NdefField.body],
    sms => const [NdefField.phone, NdefField.body],
    location => const [NdefField.latitude, NdefField.longitude],
    wifi => const [NdefField.ssid, NdefField.password],
    contact => const [NdefField.contactName, NdefField.phone, NdefField.email],
    androidApp => const [NdefField.packageName],
    mime || external => const [NdefField.type, NdefField.content, NdefField.id],
    raw => const [NdefField.type, NdefField.payload, NdefField.id],
  };
}

/// A text field of a record's form.
enum NdefField {
  url,
  text,
  language,
  phone,
  email,
  subject,
  body,
  latitude,
  longitude,
  ssid,
  password,
  contactName,
  packageName,
  type,
  content,
  payload,
  id;

  /// Whether a record cannot be made with this field left empty.
  bool requiredIn(NdefRecordKind kind) => switch (this) {
    subject || body || content || payload || id || password => false,
    phone || email => kind != NdefRecordKind.contact,
    type => kind != NdefRecordKind.raw,
    _ => true,
  };
}

/// Why a field's value cannot make a record.
enum NdefFieldError { required, invalid, tooShort, outOfRange }

/// A record being edited: the fields of its form, as typed.
///
/// [toRecord] turns it into a record once [errors] is empty. A record read
/// back with [NdefRecordDraft.fromRecord] gives the same fields, so editing a
/// record and saving it unchanged keeps it as it was.
@immutable
class NdefRecordDraft {
  NdefRecordDraft(
    this.kind, {
    Map<NdefField, String> values = const {},
    this.security = NdefWifiSecurity.wpa2,
    this.tnf = ndef.TypeNameFormat.unknown,
    this.keptId,
  }) : values = Map.unmodifiable(values);

  /// A record's fields. Records the forms cannot hold without losing
  /// something open in the raw form, byte for byte.
  factory NdefRecordDraft.fromRecord(
    ndef.NDEFRecord record, {
    String language = 'en',
  }) {
    final id = record.id == null || record.id!.isEmpty ? null : record.id;
    NdefRecordDraft draft(
      NdefRecordKind kind,
      Map<NdefField, String> values, {
      NdefWifiSecurity security = NdefWifiSecurity.wpa2,
    }) => NdefRecordDraft(
      kind,
      values: values,
      security: security,
      keptId: id == null ? null : Uint8List.fromList(id),
    );

    final uri = ndefRecordUri(record);
    if (uri != null) {
      final query = uri.queryParameters;
      switch (ndefPresetOf(record)) {
        case NdefPreset.phone:
          return draft(NdefRecordKind.phone, {NdefField.phone: uri.path});
        case NdefPreset.email:
          return draft(NdefRecordKind.email, {
            NdefField.email: uri.path,
            NdefField.subject: query['subject'] ?? '',
            NdefField.body: query['body'] ?? '',
          });
        case NdefPreset.sms:
          return draft(NdefRecordKind.sms, {
            NdefField.phone: uri.path,
            NdefField.body: query['body'] ?? '',
          });
        case NdefPreset.location:
          final geo = geoOf(uri)!;
          return draft(NdefRecordKind.location, {
            NdefField.latitude: '${geo.latitude}',
            NdefField.longitude: '${geo.longitude}',
          });
        default:
          return draft(NdefRecordKind.url, {NdefField.url: uri.toString()});
      }
    }
    if (wifiOf(record) case final wifi?) {
      return draft(NdefRecordKind.wifi, {
        NdefField.ssid: wifi.ssid,
        NdefField.password: wifi.password,
      }, security: wifi.security);
    }
    if (contactOf(record) case final contact?) {
      return draft(NdefRecordKind.contact, {
        NdefField.contactName: contact.name,
        NdefField.phone: contact.phone,
        NdefField.email: contact.email,
      });
    }
    if (androidAppOf(record) case final package?) {
      return draft(NdefRecordKind.androidApp, {NdefField.packageName: package});
    }
    if (_textOf(record) case final text?) {
      return draft(NdefRecordKind.text, {
        NdefField.text: text.text ?? '',
        NdefField.language: text.language ?? language,
      });
    }
    final idHex = id == null ? '' : _hex(id);
    if (_textPayloadOf(record) case (final kind, final type, final content)) {
      return NdefRecordDraft(
        kind,
        values: {
          NdefField.type: type,
          NdefField.content: content,
          NdefField.id: idHex,
        },
      );
    }
    return NdefRecordDraft(
      NdefRecordKind.raw,
      tnf: record.tnf,
      values: {
        NdefField.type: _hex(record.type ?? const []),
        NdefField.payload: _hex(record.payload ?? const []),
        NdefField.id: idHex,
      },
    );
  }

  /// An empty form of [kind].
  factory NdefRecordDraft.empty(
    NdefRecordKind kind, {
    String language = 'en',
  }) => NdefRecordDraft(
    kind,
    values: kind == NdefRecordKind.text
        ? {NdefField.language: language}
        : const {},
  );

  final NdefRecordKind kind;
  final Map<NdefField, String> values;

  /// The security of a Wi-Fi record.
  final NdefWifiSecurity security;

  /// The type name format of a raw record.
  final ndef.TypeNameFormat tnf;

  /// The identifier of a record whose form has no field for it, which saving
  /// keeps.
  final Uint8List? keptId;

  /// The fields of the form, with the password left out of an open network.
  List<NdefField> get fields => [
    for (final field in kind.fields)
      if (field != NdefField.password || security != NdefWifiSecurity.open)
        field,
  ];

  String valueOf(NdefField field) => values[field] ?? '';

  NdefRecordDraft copyWith({
    Map<NdefField, String>? values,
    NdefWifiSecurity? security,
    ndef.TypeNameFormat? tnf,
  }) => NdefRecordDraft(
    kind,
    values: values ?? this.values,
    security: security ?? this.security,
    tnf: tnf ?? this.tnf,
    keptId: keptId,
  );

  /// The fields that keep this draft from making a record.
  Map<NdefField, NdefFieldError> get errors => {
    for (final field in fields) field: ?_errorOf(field),
  };

  NdefFieldError? _errorOf(NdefField field) {
    final raw = valueOf(field);
    final value = raw.trim();
    if (value.isEmpty) {
      if (field == NdefField.password && security != NdefWifiSecurity.open) {
        return NdefFieldError.required;
      }
      if (field == NdefField.text && raw.isNotEmpty) return null;
      return field.requiredIn(kind) ? NdefFieldError.required : null;
    }
    return switch (field) {
      NdefField.url => _linkOf(value) == null ? NdefFieldError.invalid : null,
      NdefField.language =>
        value.length <= 63 &&
                RegExp(r'^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$').hasMatch(value)
            ? null
            : NdefFieldError.invalid,
      NdefField.phone =>
        // A contact's phone is written as it is typed.
        kind == NdefRecordKind.contact || isPhoneNumber(value)
            ? null
            : NdefFieldError.invalid,
      NdefField.email => isEmailAddress(value) ? null : NdefFieldError.invalid,
      NdefField.latitude => _coordinateError(value, 90),
      NdefField.longitude => _coordinateError(value, 180),
      NdefField.ssid =>
        utf8.encode(raw).length <= 32 ? null : NdefFieldError.invalid,
      NdefField.password =>
        raw.length < 8
            ? NdefFieldError.tooShort
            : isWifiPassword(raw)
            ? null
            : NdefFieldError.invalid,
      NdefField.packageName =>
        isAndroidPackage(value) ? null : NdefFieldError.invalid,
      NdefField.type => _typeError(value),
      NdefField.payload => _payloadError(value),
      NdefField.id => switch (_unhex(value)) {
        final bytes? when bytes.length <= 255 => null,
        _ => NdefFieldError.invalid,
      },
      _ => null,
    };
  }

  NdefFieldError? _typeError(String value) {
    if (kind == NdefRecordKind.mime) {
      return _mimeType.hasMatch(value) ? null : NdefFieldError.invalid;
    }
    if (kind == NdefRecordKind.external) {
      return _externalType.hasMatch(value) ? null : NdefFieldError.invalid;
    }
    final bytes = _unhex(value);
    if (bytes == null || bytes.length > 255) return NdefFieldError.invalid;
    // Empty and unknown records have no type.
    return const {
          ndef.TypeNameFormat.empty,
          ndef.TypeNameFormat.unknown,
          ndef.TypeNameFormat.unchanged,
        }.contains(tnf)
        ? NdefFieldError.invalid
        : null;
  }

  NdefFieldError? _payloadError(String value) {
    if (_unhex(value) == null) return NdefFieldError.invalid;
    return tnf == ndef.TypeNameFormat.empty ? NdefFieldError.invalid : null;
  }

  /// The record of this draft. Throws a [FormatException] while [errors] is
  /// not empty.
  ndef.NDEFRecord toRecord() {
    if (errors.isNotEmpty) throw const FormatException();
    String v(NdefField field) => valueOf(field);
    final record = switch (kind) {
      NdefRecordKind.url => ndef.UriRecord.fromString(
        _linkOf(v(NdefField.url).trim())!,
      ),
      NdefRecordKind.text => ndef.TextRecord(
        text: v(NdefField.text),
        language: v(NdefField.language).trim(),
      ),
      NdefRecordKind.phone => phoneRecord(v(NdefField.phone)),
      NdefRecordKind.email => emailRecord(
        v(NdefField.email),
        subject: v(NdefField.subject),
        body: v(NdefField.body),
      ),
      NdefRecordKind.sms => smsRecord(
        v(NdefField.phone),
        body: v(NdefField.body),
      ),
      NdefRecordKind.location => locationRecord(
        double.parse(v(NdefField.latitude).trim()),
        double.parse(v(NdefField.longitude).trim()),
      ),
      NdefRecordKind.wifi => wifiRecord(
        v(NdefField.ssid),
        security: security,
        password: v(NdefField.password),
      ),
      NdefRecordKind.contact => contactRecord(
        name: v(NdefField.contactName),
        phone: v(NdefField.phone),
        email: v(NdefField.email),
      ),
      NdefRecordKind.androidApp => androidAppRecord(v(NdefField.packageName)),
      NdefRecordKind.mime || NdefRecordKind.external => ndef.NDEFRecord(
        tnf: kind == NdefRecordKind.mime
            ? ndef.TypeNameFormat.media
            : ndef.TypeNameFormat.nfcExternal,
        type: Uint8List.fromList(
          utf8.encode(v(NdefField.type).trim().toLowerCase()),
        ),
        payload: Uint8List.fromList(utf8.encode(v(NdefField.content))),
      ),
      NdefRecordKind.raw => ndef.NDEFRecord(
        tnf: tnf,
        type: _unhex(v(NdefField.type))!,
        payload: _unhex(v(NdefField.payload))!,
      ),
    };
    final id = kind.isAdvanced ? _unhex(v(NdefField.id))! : keptId;
    record.id = id == null || id.isEmpty ? null : id;
    // Encode it once, so a record the tag could not hold fails here.
    NdefCard.fromRecords([record]);
    return record;
  }
}

/// The size [records] take on a tag, as one NDEF message.
int ndefMessageSize(List<ndef.NDEFRecord> records) =>
    records.isEmpty ? 0 : ndef.encodeNdefMessage(records).length;

final _mimeType = RegExp(
  r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$',
  caseSensitive: false,
);
final _externalType = RegExp(
  r'^[a-z0-9.-]+:[a-z0-9._-]+$',
  caseSensitive: false,
);

/// The link [value] names: as typed when it has a scheme, or a web address
/// for a bare host such as `example.com`.
String? _linkOf(String value) {
  if (value.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme) {
    return value.length > uri.scheme.length + 1 ? value : null;
  }
  return RegExp(r'^[^/.:]+(\.[^/.:]+)+(:\d+)?(/.*)?$').hasMatch(value)
      ? 'https://$value'
      : null;
}

NdefFieldError? _coordinateError(String value, double limit) {
  final number = double.tryParse(value);
  if (number == null || !number.isFinite) return NdefFieldError.invalid;
  return number.abs() > limit ? NdefFieldError.outOfRange : null;
}

ndef.TextRecord? _textOf(ndef.NDEFRecord record) {
  if (record.tnf != ndef.TypeNameFormat.nfcWellKnown ||
      !listEquals(record.type, const [0x54])) {
    return null;
  }
  try {
    final decoded = ndef.NDEFRecord.doDecode(
      record.tnf,
      record.type!,
      record.payload ?? Uint8List(0),
      id: record.id,
    );
    return decoded is ndef.TextRecord ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// The kind, type and content of a MIME or external record whose type and
/// payload are plain text, which the text forms can edit without loss.
(NdefRecordKind, String, String)? _textPayloadOf(ndef.NDEFRecord record) {
  final kind = switch (record.tnf) {
    ndef.TypeNameFormat.media => NdefRecordKind.mime,
    ndef.TypeNameFormat.nfcExternal => NdefRecordKind.external,
    _ => null,
  };
  if (kind == null) return null;
  final String type;
  final String content;
  try {
    type = utf8.decode(record.type ?? const []);
    content = utf8.decode(record.payload ?? const []);
  } on FormatException {
    return null;
  }
  if (content.runes.any((r) => r < 32 && r != 9 && r != 10 && r != 13)) {
    return null;
  }
  final pattern = kind == NdefRecordKind.mime ? _mimeType : _externalType;
  // Saving writes the type in lower case; a type in any other case would
  // change.
  if (!pattern.hasMatch(type) || type != type.toLowerCase()) return null;
  return (kind, type, content);
}

String _hex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join(' ')
    .toUpperCase();

Uint8List? _unhex(String value) {
  final clean = value.replaceAll(RegExp(r'[\s:]'), '');
  if (!RegExp(r'^(?:[0-9a-fA-F]{2})*$').hasMatch(clean)) return null;
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
