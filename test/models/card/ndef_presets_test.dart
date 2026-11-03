import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/ndef_presets.dart';
import 'package:ndef/ndef.dart' as ndef;

/// [record] as a tag would hand it back: encoded, then decoded.
ndef.NDEFRecord _readBack(ndef.NDEFRecord record) =>
    NdefCard.fromRecords([record]).records.single;

void main() {
  test('phone, SMS and location links read back as their presets', () {
    final phone = _readBack(phoneRecord(' +81 3-1234-5678 '));
    expect(ndefRecordUri(phone).toString(), 'tel:+813-1234-5678');
    expect(ndefPresetOf(phone), NdefPreset.phone);

    final sms = _readBack(smsRecord('10086', body: 'hi there'));
    expect(ndefRecordUri(sms).toString(), 'sms:10086?body=hi%20there');
    expect(ndefPresetOf(sms), NdefPreset.sms);
    expect(ndefRecordUri(sms)!.queryParameters['body'], 'hi there');

    final location = _readBack(locationRecord(35.6812, 139.7671));
    expect(ndefPresetOf(location), NdefPreset.location);
    expect(geoOf(ndefRecordUri(location)!), (
      latitude: 35.6812,
      longitude: 139.7671,
    ));

    expect(() => phoneRecord('call me'), throwsFormatException);
    expect(() => locationRecord(91, 0), throwsFormatException);
    expect(
      ndefPresetOf(ndef.UriRecord.fromString('https://example.org')),
      isNull,
    );
  });

  test('a mail link encodes spaces and plus signs for mail clients', () {
    final email = _readBack(
      emailRecord('a@example.org', subject: '1 + 1', body: 'two words'),
    );
    expect(
      ndefRecordUri(email).toString(),
      'mailto:a@example.org?subject=1%20%2B%201&body=two%20words',
    );
    expect(ndefPresetOf(email), NdefPreset.email);
    expect(ndefRecordUri(email)!.queryParameters['subject'], '1 + 1');
    expect(() => emailRecord('not an address'), throwsFormatException);
  });

  test('a Wi-Fi record joins the network it was made for', () {
    final record = _readBack(
      wifiRecord(
        'HINATA',
        security: NdefWifiSecurity.wpa2,
        password: 'password1',
      ),
    );
    expect(ndefPresetOf(record), NdefPreset.wifi);
    expect(wifiOf(record), (
      ssid: 'HINATA',
      security: NdefWifiSecurity.wpa2,
      password: 'password1',
    ));

    final open = _readBack(
      wifiRecord('Guest', security: NdefWifiSecurity.open),
    );
    expect(wifiOf(open)?.security, NdefWifiSecurity.open);
    expect(
      () => wifiRecord('HINATA', security: NdefWifiSecurity.wpa3),
      throwsFormatException,
    );
  });

  test('a contact keeps its fields, escaped', () {
    final record = _readBack(
      contactRecord(name: 'Neri, Moe', phone: '123', email: 'a@example.org'),
    );
    expect(utf8.decode(record.payload!), contains('FN:Neri\\, Moe\r\n'));
    expect(ndefPresetOf(record), NdefPreset.contact);
    expect(contactOf(record), (
      name: 'Neri, Moe',
      phone: '123',
      email: 'a@example.org',
    ));
  });

  test('a vCard with more than the form holds stays a MIME record', () {
    final record = ndef.NDEFRecord(
      tnf: ndef.TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode('text/vcard')),
      payload: Uint8List.fromList(
        utf8.encode('BEGIN:VCARD\r\nFN:A\r\nORG:B\r\nEND:VCARD\r\n'),
      ),
    );
    expect(contactOf(record), isNull);
    expect(ndefPresetOf(record), isNull);
  });

  test('an Android app record names its package', () {
    final record = _readBack(androidAppRecord('moe.neri.hinatago'));
    expect(ndefPresetOf(record), NdefPreset.androidApp);
    expect(androidAppOf(record), 'moe.neri.hinatago');
    expect(() => androidAppRecord('hinata'), throwsFormatException);
  });
}
