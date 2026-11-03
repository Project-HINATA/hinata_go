import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../l10n/l10n.dart';
import '../models/card/ndef.dart';
import '../models/card/ndef_presets.dart';

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
