import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../l10n/l10n.dart';
import '../models/card/ndef.dart';
import '../models/card/ndef_presets.dart';
import '../models/card/ndef_record_draft.dart';

String ndefRecordLabel(ndef.NDEFRecord record) {
  final preset = ndefPresetOf(record);
  if (preset != null) return ndefPresetLabel(preset);
  if (ndefRecordUri(record) != null) return l10n.ndefLink;
  if (record.tnf == ndef.TypeNameFormat.nfcWellKnown &&
      listEquals(record.type, [0x54])) {
    return l10n.ndefText;
  }
  final type = utf8.decode(record.type ?? [], allowMalformed: true);
  if (record.tnf == ndef.TypeNameFormat.media) return 'MIME · $type';
  if (record.tnf == ndef.TypeNameFormat.nfcExternal) {
    return '${l10n.ndefExternal} · $type';
  }
  return l10n.ndefRaw;
}

String ndefPresetLabel(NdefPreset preset) => switch (preset) {
  NdefPreset.phone => l10n.ndefPhone,
  NdefPreset.email => l10n.ndefEmail,
  NdefPreset.sms => l10n.ndefSms,
  NdefPreset.location => l10n.ndefLocation,
  NdefPreset.wifi => l10n.ndefWifi,
  NdefPreset.contact => l10n.ndefContact,
  NdefPreset.androidApp => l10n.ndefAndroidApp,
};

IconData ndefRecordIcon(ndef.NDEFRecord record) {
  switch (ndefPresetOf(record)) {
    case NdefPreset.phone:
      return Icons.phone_outlined;
    case NdefPreset.email:
      return Icons.email_outlined;
    case NdefPreset.sms:
      return Icons.sms_outlined;
    case NdefPreset.location:
      return Icons.place_outlined;
    case NdefPreset.wifi:
      return Icons.wifi;
    case NdefPreset.contact:
      return Icons.person_outline;
    case NdefPreset.androidApp:
      return Icons.android;
    case null:
      break;
  }
  if (ndefRecordUri(record) != null) return Icons.link;
  if (record.tnf == ndef.TypeNameFormat.media) {
    return Icons.description_outlined;
  }
  if (record.tnf == ndef.TypeNameFormat.nfcExternal) {
    return Icons.extension_outlined;
  }
  if (record.tnf == ndef.TypeNameFormat.nfcWellKnown &&
      listEquals(record.type, [0x54])) {
    return Icons.notes;
  }
  return Icons.data_object;
}

String ndefTnfLabel(ndef.TypeNameFormat tnf) => switch (tnf) {
  ndef.TypeNameFormat.empty => l10n.ndefTnfEmpty,
  ndef.TypeNameFormat.nfcWellKnown => l10n.ndefTnfWellKnown,
  ndef.TypeNameFormat.media => 'MIME',
  ndef.TypeNameFormat.absoluteURI => l10n.ndefLink,
  ndef.TypeNameFormat.nfcExternal => l10n.ndefExternal,
  ndef.TypeNameFormat.unknown => l10n.ndefTnfUnknown,
  ndef.TypeNameFormat.unchanged => l10n.ndefTnfUnchanged,
};

String ndefKindLabel(NdefRecordKind kind) => switch (kind) {
  NdefRecordKind.url => l10n.ndefLink,
  NdefRecordKind.text => l10n.ndefText,
  NdefRecordKind.phone => l10n.ndefPhone,
  NdefRecordKind.email => l10n.ndefEmail,
  NdefRecordKind.sms => l10n.ndefSms,
  NdefRecordKind.location => l10n.ndefLocation,
  NdefRecordKind.wifi => l10n.ndefWifi,
  NdefRecordKind.contact => l10n.ndefContact,
  NdefRecordKind.androidApp => l10n.ndefAndroidApp,
  NdefRecordKind.mime => 'MIME',
  NdefRecordKind.external => l10n.ndefExternal,
  NdefRecordKind.raw => l10n.ndefRaw,
};

String ndefKindDescription(NdefRecordKind kind) => switch (kind) {
  NdefRecordKind.url => l10n.ndefKindUrlDescription,
  NdefRecordKind.text => l10n.ndefKindTextDescription,
  NdefRecordKind.phone => l10n.ndefKindPhoneDescription,
  NdefRecordKind.email => l10n.ndefKindEmailDescription,
  NdefRecordKind.sms => l10n.ndefKindSmsDescription,
  NdefRecordKind.location => l10n.ndefKindLocationDescription,
  NdefRecordKind.wifi => l10n.ndefKindWifiDescription,
  NdefRecordKind.contact => l10n.ndefKindContactDescription,
  NdefRecordKind.androidApp => l10n.ndefKindAndroidAppDescription,
  NdefRecordKind.mime => l10n.ndefKindMimeDescription,
  NdefRecordKind.external => l10n.ndefKindExternalDescription,
  NdefRecordKind.raw => l10n.ndefKindRawDescription,
};

IconData ndefKindIcon(NdefRecordKind kind) => switch (kind) {
  NdefRecordKind.url => Icons.link,
  NdefRecordKind.text => Icons.notes,
  NdefRecordKind.phone => Icons.phone_outlined,
  NdefRecordKind.email => Icons.email_outlined,
  NdefRecordKind.sms => Icons.sms_outlined,
  NdefRecordKind.location => Icons.place_outlined,
  NdefRecordKind.wifi => Icons.wifi,
  NdefRecordKind.contact => Icons.person_outline,
  NdefRecordKind.androidApp => Icons.android,
  NdefRecordKind.mime => Icons.description_outlined,
  NdefRecordKind.external => Icons.extension_outlined,
  NdefRecordKind.raw => Icons.data_object,
};

String ndefFieldLabel(NdefField field, NdefRecordKind kind) => switch (field) {
  NdefField.url => l10n.ndefLink,
  NdefField.text => l10n.ndefContent,
  NdefField.language => l10n.ndefLanguage,
  NdefField.phone => l10n.ndefPhoneNumber,
  NdefField.email => l10n.ndefEmailAddress,
  NdefField.subject => l10n.ndefEmailSubject,
  NdefField.body => l10n.ndefMessageBody,
  NdefField.latitude => l10n.ndefLatitude,
  NdefField.longitude => l10n.ndefLongitude,
  NdefField.ssid => l10n.ndefWifiSsid,
  NdefField.password => l10n.ndefWifiPassword,
  NdefField.contactName => l10n.ndefContactName,
  NdefField.packageName => l10n.ndefPackageName,
  NdefField.type => switch (kind) {
    NdefRecordKind.mime => l10n.ndefMimeType,
    NdefRecordKind.external => l10n.ndefExternalTypeName,
    _ => l10n.ndefTypeHex,
  },
  NdefField.content => l10n.ndefContent,
  NdefField.payload => l10n.ndefPayloadHex,
  NdefField.id => l10n.ndefIdHex,
};

/// The example a field shows while it is empty.
String? ndefFieldPlaceholder(NdefField field, NdefRecordKind kind) =>
    switch (field) {
      NdefField.url => 'https://example.com',
      NdefField.text => l10n.ndefTextPlaceholder,
      NdefField.phone => '+86 138 0000 0000',
      NdefField.email => 'name@example.com',
      NdefField.latitude => '35.6812',
      NdefField.longitude => '139.7671',
      NdefField.packageName => 'com.example.app',
      NdefField.type => switch (kind) {
        NdefRecordKind.mime => 'text/plain',
        NdefRecordKind.external => 'example.com:type',
        _ => '55',
      },
      NdefField.payload || NdefField.id => '0A 1B 2C',
      _ => null,
    };

String ndefFieldErrorText(NdefField field, NdefFieldError error) =>
    switch (error) {
      NdefFieldError.required => l10n.ndefFieldRequired,
      NdefFieldError.tooShort => l10n.ndefWifiPasswordShort,
      NdefFieldError.outOfRange =>
        field == NdefField.latitude
            ? l10n.ndefLatitudeRange
            : l10n.ndefLongitudeRange,
      NdefFieldError.invalid => l10n.ndefFieldInvalid,
    };

/// What a record holds, in a line or two for a list of records.
String ndefRecordSummary(ndef.NDEFRecord record) {
  if (wifiOf(record) case final wifi?) {
    final security = switch (wifi.security) {
      NdefWifiSecurity.wpa2 => 'WPA2',
      NdefWifiSecurity.wpa3 => 'WPA3',
      NdefWifiSecurity.open => l10n.ndefWifiOpenShort,
    };
    return '${wifi.ssid} · $security';
  }
  if (contactOf(record) case final contact?) {
    return [
      contact.name,
      contact.phone,
      contact.email,
    ].where((value) => value.isNotEmpty).join(' · ');
  }
  if (androidAppOf(record) case final package?) return package;
  return ndefRecordValue(record);
}
