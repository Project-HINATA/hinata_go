import 'dart:convert';
import 'dart:typed_data';

import 'package:ndef/ndef.dart' as ndef;

import 'ndef.dart';

/// The common records the NDEF editor offers as forms, built from their
/// fields and read back from a record for editing.
enum NdefPreset { phone, email, sms, location, wifi, contact, androidApp }

/// The preset [record] is, or null when it is none of them.
NdefPreset? ndefPresetOf(ndef.NDEFRecord record) {
  final uri = ndefRecordUri(record);
  if (uri != null) {
    return switch (uri.scheme.toLowerCase()) {
      'tel' => NdefPreset.phone,
      'mailto' => NdefPreset.email,
      'sms' || 'smsto' => NdefPreset.sms,
      'geo' when geoOf(uri) != null => NdefPreset.location,
      _ => null,
    };
  }
  if (wifiOf(record) != null) return NdefPreset.wifi;
  if (contactOf(record) != null) return NdefPreset.contact;
  if (androidAppOf(record) != null) return NdefPreset.androidApp;
  return null;
}

/// A `tel:` link to [number], without the spaces a link cannot hold.
ndef.NDEFRecord phoneRecord(String number) {
  final value = _phoneNumber(number);
  return ndef.UriRecord.fromString('tel:$value');
}

/// A `mailto:` link, with the subject and body percent-encoded: a `+` in a
/// query means a plus sign to mail clients, not a space.
ndef.NDEFRecord emailRecord(
  String address, {
  String subject = '',
  String body = '',
}) {
  final value = address.trim();
  if (!isEmailAddress(value)) throw const FormatException();
  final query = [
    if (subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
    if (body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
  ];
  return ndef.UriRecord.fromString(
    'mailto:$value${query.isEmpty ? '' : '?${query.join('&')}'}',
  );
}

/// An `sms:` link to [number] with [body] filled in.
ndef.NDEFRecord smsRecord(String number, {String body = ''}) {
  final value = _phoneNumber(number);
  return ndef.UriRecord.fromString(
    'sms:$value${body.isEmpty ? '' : '?body=${Uri.encodeComponent(body)}'}',
  );
}

/// A `geo:` link to a point.
ndef.NDEFRecord locationRecord(double latitude, double longitude) {
  if (latitude.abs() > 90 || longitude.abs() > 180) {
    throw const FormatException();
  }
  return ndef.UriRecord.fromString('geo:$latitude,$longitude');
}

/// The point of a `geo:` link, or null when it names none.
({double latitude, double longitude})? geoOf(Uri uri) {
  final parts = uri.path.split(';').first.split(',');
  if (parts.length < 2) return null;
  final latitude = double.tryParse(parts[0]);
  final longitude = double.tryParse(parts[1]);
  if (latitude == null || longitude == null) return null;
  return (latitude: latitude, longitude: longitude);
}

/// The Wi-Fi security a network asks for, as the editor offers it.
enum NdefWifiSecurity { open, wpa2, wpa3 }

/// A Wi-Fi Simple Configuration record that joins a network.
ndef.NDEFRecord wifiRecord(
  String ssid, {
  required NdefWifiSecurity security,
  String password = '',
}) {
  if (ssid.isEmpty || utf8.encode(ssid).length > 32) {
    throw const FormatException();
  }
  if (security != NdefWifiSecurity.open && !isWifiPassword(password)) {
    throw const FormatException();
  }
  return ndef.WifiRecord(
    ssid: ssid,
    networkKey: security == NdefWifiSecurity.open ? null : password,
    authenticationType: switch (security) {
      NdefWifiSecurity.open => ndef.WifiAuthenticationType.open,
      NdefWifiSecurity.wpa2 => ndef.WifiAuthenticationType.wpaWpa2Personal,
      NdefWifiSecurity.wpa3 => ndef.WifiAuthenticationType.wpa3Personal,
    },
    encryptionType: security == NdefWifiSecurity.open
        ? ndef.WifiEncryptionType.none
        : ndef.WifiEncryptionType.aes,
  );
}

/// The network a Wi-Fi record joins, or null when [record] is not one.
({String ssid, NdefWifiSecurity security, String password})? wifiOf(
  ndef.NDEFRecord record,
) {
  final decoded = _decode(record);
  if (decoded is! ndef.WifiRecord) return null;
  final ssid = decoded.ssid;
  if (ssid == null) return null;
  return (
    ssid: ssid,
    security: switch (decoded.authenticationType) {
      ndef.WifiAuthenticationType.open => NdefWifiSecurity.open,
      ndef.WifiAuthenticationType.wpa3Personal => NdefWifiSecurity.wpa3,
      _ => NdefWifiSecurity.wpa2,
    },
    password: decoded.networkKey ?? '',
  );
}

/// A vCard 3.0 contact. Only the fields given are written.
ndef.NDEFRecord contactRecord({
  required String name,
  String phone = '',
  String email = '',
}) {
  if (name.trim().isEmpty) throw const FormatException();
  final card = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    'N:${_escape(name.trim())};;;;',
    'FN:${_escape(name.trim())}',
    if (phone.trim().isNotEmpty) 'TEL:${_escape(phone.trim())}',
    if (email.trim().isNotEmpty) 'EMAIL:${_escape(email.trim())}',
    'END:VCARD',
    '',
  ].join('\r\n');
  return ndef.NDEFRecord(
    tnf: ndef.TypeNameFormat.media,
    type: Uint8List.fromList(utf8.encode(_vcardType)),
    payload: Uint8List.fromList(utf8.encode(card)),
  );
}

/// The contact a vCard record holds, or null when [record] is not one, or
/// holds more than the editor's fields, which editing would lose.
({String name, String phone, String email})? contactOf(ndef.NDEFRecord record) {
  if (record.tnf != ndef.TypeNameFormat.media) return null;
  final type = utf8.decode(record.type ?? const [], allowMalformed: true);
  if (!const {_vcardType, 'text/x-vcard'}.contains(type.toLowerCase())) {
    return null;
  }
  final String text;
  try {
    text = utf8.decode(record.payload ?? const []);
  } on FormatException {
    return null;
  }
  var name = '';
  var phone = '';
  var email = '';
  for (final line in const LineSplitter().convert(text)) {
    if (line.isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon < 0) return null;
    final key = line.substring(0, colon).toUpperCase();
    final value = _unescape(line.substring(colon + 1));
    switch (key) {
      case 'BEGIN' || 'END' || 'VERSION' || 'N':
        continue;
      case 'FN' when name.isEmpty:
        name = value;
      case 'TEL' when phone.isEmpty:
        phone = value;
      case 'EMAIL' when email.isEmpty:
        email = value;
      default:
        return null;
    }
  }
  return name.isEmpty ? null : (name: name, phone: phone, email: email);
}

/// An Android Application Record: Android opens [package], or its store
/// page when it is not installed.
ndef.NDEFRecord androidAppRecord(String package) {
  final value = package.trim();
  if (!isAndroidPackage(value)) throw const FormatException();
  return ndef.AARRecord(packageName: value);
}

/// The package an Android Application Record opens, or null when [record]
/// is not one.
String? androidAppOf(ndef.NDEFRecord record) {
  final decoded = _decode(record);
  return decoded is ndef.AARRecord ? decoded.packageName : null;
}

/// Whether [number], without its spaces, can go in a `tel:` or `sms:` link.
bool isPhoneNumber(String number) =>
    _phonePattern.hasMatch(number.replaceAll(RegExp(r'\s'), ''));

bool isEmailAddress(String address) =>
    RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(address.trim());

bool isAndroidPackage(String package) =>
    RegExp(r'^[a-zA-Z]\w*(\.[a-zA-Z]\w*)+$').hasMatch(package.trim());

/// Whether a Wi-Fi record can hold [password]: WPA asks for 8 to 63
/// characters.
bool isWifiPassword(String password) =>
    password.length >= 8 && password.length <= 63;

const _vcardType = 'text/vcard';
final _phonePattern = RegExp(r'^\+?[0-9*#()\-]{1,32}$');

/// [number] without spaces, or throws when it is not a phone number.
String _phoneNumber(String number) {
  if (!isPhoneNumber(number)) throw const FormatException();
  return number.replaceAll(RegExp(r'\s'), '');
}

ndef.NDEFRecord? _decode(ndef.NDEFRecord record) {
  try {
    return ndef.NDEFRecord.doDecode(
      record.tnf,
      record.type ?? Uint8List(0),
      record.payload ?? Uint8List(0),
      id: record.id,
    );
  } catch (_) {
    return null;
  }
}

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;')
    .replaceAll('\n', r'\n');

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'\\(.)'),
  (match) => match[1] == 'n' || match[1] == 'N' ? '\n' : match[1]!,
);
