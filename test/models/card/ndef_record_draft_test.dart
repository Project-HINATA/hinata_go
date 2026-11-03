import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/ndef.dart';
import 'package:hinata_go/models/card/ndef_presets.dart';
import 'package:hinata_go/models/card/ndef_record_draft.dart';
import 'package:ndef/ndef.dart' as ndef;

/// [record] as a tag would hand it back: encoded, then decoded.
ndef.NDEFRecord _readBack(ndef.NDEFRecord record) =>
    NdefCard.fromRecords([record]).records.single;

Uint8List _bytes(ndef.NDEFRecord record) => ndef.encodeNdefMessage([record]);

void main() {
  test('each kind reads back to its own form and saves unchanged', () {
    final records = {
      NdefRecordKind.url: ndef.UriRecord.fromString('https://neri.moe'),
      NdefRecordKind.text: ndef.TextRecord(text: 'hello', language: 'ja'),
      NdefRecordKind.phone: phoneRecord('10086'),
      NdefRecordKind.email: emailRecord('a@example.org', subject: 'hi'),
      NdefRecordKind.sms: smsRecord('10086', body: 'hi'),
      NdefRecordKind.location: locationRecord(35.6812, 139.7671),
      NdefRecordKind.wifi: wifiRecord(
        'HINATA',
        security: NdefWifiSecurity.wpa2,
        password: 'password1',
      ),
      NdefRecordKind.contact: contactRecord(name: 'Neri', phone: '123'),
      NdefRecordKind.androidApp: androidAppRecord('moe.neri.hinatago'),
      NdefRecordKind.mime: ndef.NDEFRecord(
        tnf: ndef.TypeNameFormat.media,
        type: Uint8List.fromList(utf8.encode('application/json')),
        payload: Uint8List.fromList(utf8.encode('{}')),
        id: Uint8List.fromList([1, 2]),
      ),
      NdefRecordKind.external: ndef.NDEFRecord(
        tnf: ndef.TypeNameFormat.nfcExternal,
        type: Uint8List.fromList(utf8.encode('neri.moe:hinata')),
        payload: Uint8List.fromList(utf8.encode('data')),
      ),
      NdefRecordKind.raw: ndef.NDEFRecord(
        tnf: ndef.TypeNameFormat.media,
        type: Uint8List.fromList(utf8.encode('application/octet-stream')),
        payload: Uint8List.fromList([0, 0xFF, 1]),
      ),
    };
    expect(records.keys, NdefRecordKind.values);
    for (final MapEntry(key: kind, value: record) in records.entries) {
      final read = _readBack(record);
      final draft = NdefRecordDraft.fromRecord(read);
      expect(draft.kind, kind, reason: '$kind');
      expect(draft.errors, isEmpty, reason: '$kind');
      expect(_bytes(draft.toRecord()), _bytes(read), reason: '$kind');
    }
  });

  test('a preset record keeps its identifier', () {
    final record = ndef.UriRecord.fromString('tel:10086')
      ..id = Uint8List.fromList([7]);
    final draft = NdefRecordDraft.fromRecord(_readBack(record));
    expect(draft.kind, NdefRecordKind.phone);
    final changed = draft.copyWith(values: {NdefField.phone: '10010'});
    expect(changed.toRecord().id, [7]);
  });

  test('empty forms point at their required fields', () {
    expect(NdefRecordDraft.empty(NdefRecordKind.email).errors, {
      NdefField.email: NdefFieldError.required,
    });
    expect(NdefRecordDraft.empty(NdefRecordKind.contact).errors, {
      NdefField.contactName: NdefFieldError.required,
    });
    // A new text record starts in the given language.
    final text = NdefRecordDraft.empty(NdefRecordKind.text, language: 'zh');
    expect(text.valueOf(NdefField.language), 'zh');
    expect(text.errors, {NdefField.text: NdefFieldError.required});
    expect(NdefRecordDraft.empty(NdefRecordKind.raw).errors, isEmpty);
    expect(
      () => NdefRecordDraft.empty(NdefRecordKind.url).toRecord(),
      throwsFormatException,
    );
  });

  test('invalid values are flagged on their own field', () {
    NdefRecordDraft draft(NdefRecordKind kind, Map<NdefField, String> values) =>
        NdefRecordDraft(kind, values: values);

    expect(draft(NdefRecordKind.url, {NdefField.url: 'not a link'}).errors, {
      NdefField.url: NdefFieldError.invalid,
    });
    // A bare host is a web address.
    expect(
      ndefRecordUri(
        draft(NdefRecordKind.url, {NdefField.url: 'neri.moe/go'}).toRecord(),
      ).toString(),
      'https://neri.moe/go',
    );
    expect(
      draft(NdefRecordKind.location, {
        NdefField.latitude: '91',
        NdefField.longitude: 'east',
      }).errors,
      {
        NdefField.latitude: NdefFieldError.outOfRange,
        NdefField.longitude: NdefFieldError.invalid,
      },
    );
    expect(
      draft(NdefRecordKind.wifi, {
        NdefField.ssid: 'HINATA',
        NdefField.password: 'short',
      }).errors,
      {NdefField.password: NdefFieldError.tooShort},
    );
    expect(
      NdefRecordDraft(
        NdefRecordKind.wifi,
        values: const {NdefField.ssid: 'Guest', NdefField.password: 'x'},
        security: NdefWifiSecurity.open,
      ).errors,
      isEmpty,
    );
    expect(
      draft(NdefRecordKind.contact, {
        NdefField.contactName: 'Neri',
        NdefField.email: 'nobody',
      }).errors,
      {NdefField.email: NdefFieldError.invalid},
    );
    expect(draft(NdefRecordKind.mime, {NdefField.type: 'json'}).errors, {
      NdefField.type: NdefFieldError.invalid,
    });
    expect(
      draft(NdefRecordKind.raw, {
        NdefField.payload: '0G',
        NdefField.id: '01 02',
      }).errors,
      {NdefField.payload: NdefFieldError.invalid},
    );
    // An unknown record has no type.
    expect(draft(NdefRecordKind.raw, {NdefField.type: '55'}).errors, {
      NdefField.type: NdefFieldError.invalid,
    });
  });

  test('the message size counts the records as one message', () {
    final records = [
      ndef.TextRecord(text: 'a', language: 'en'),
      ndef.UriRecord.fromString('https://neri.moe'),
    ];
    expect(ndefMessageSize(records), ndef.encodeNdefMessage(records).length);
    expect(ndefMessageSize(const []), 0);
  });
}
