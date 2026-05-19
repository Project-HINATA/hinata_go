import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../card/card_tag.dart';
import 'nfc_tag_converter.dart';
import 'phone_nfc_transceiver.dart';

enum PhoneNfcAvailability { available, disabled, notSupported }

class PhoneNfcPollResult {
  const PhoneNfcPollResult({required this.tag, required this.transceiver});

  final CardTag tag;
  final PhoneNfcTransceiver transceiver;
}

class PhoneNfcReader {
  Stream<NFCTag> get tagStream => FlutterNfcKit.tagStream;

  Future<void> relayAndroidInitialTag({required String channelName}) async {
    if (kIsWeb) return;

    final methodChannel = MethodChannel(channelName);
    await methodChannel.invokeMethod<void>('getInitialTag');
  }

  Future<PhoneNfcAvailability> availability() async {
    if (kIsWeb) {
      return PhoneNfcAvailability.notSupported;
    }

    final availability = await FlutterNfcKit.nfcAvailability;
    return switch (availability) {
      NFCAvailability.available => PhoneNfcAvailability.available,
      NFCAvailability.disabled => PhoneNfcAvailability.disabled,
      NFCAvailability.not_supported => PhoneNfcAvailability.notSupported,
    };
  }

  Future<PhoneNfcPollResult?> poll({String? iosAlertMessage}) async {
    final tag = await FlutterNfcKit.poll(
      iosAlertMessage: iosAlertMessage ?? '',
      readIso18092: true,
      readIso14443B: false,
      readIso15693: true,
    );
    return resolve(tag);
  }

  PhoneNfcPollResult? resolve(NFCTag tag) {
    final cardTag = tag.toCardTag();
    if (cardTag == null) return null;

    return PhoneNfcPollResult(tag: cardTag, transceiver: PhoneNfcTransceiver());
  }

  Future<void> finish() => FlutterNfcKit.finish();
}
