import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_nfc_kit/method');

  test(
    'forwards iOS composite-tag polling options to the native plugin',
    () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return jsonEncode({
              'type': 'iso18092',
              'id': '0102030405060708',
              'standard': 'ISO 18092 (FeliCa)',
            });
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await FlutterNfcKit.poll(
        iosCheckNDEF: false,
        iosPreferFelicaWhenMixed: true,
        readIso18092: true,
      );

      expect(capturedCall?.method, 'poll');
      final arguments = capturedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['iosCheckNDEF'], isFalse);
      expect(arguments['iosPreferFelicaWhenMixed'], isTrue);
    },
  );
}
