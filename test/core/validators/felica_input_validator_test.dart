import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/validators/felica_input_validator.dart';

void main() {
  test('IDm and PMm take 16 hex digits with optional separators', () {
    expect(FelicaInputValidator.parseBytes8('012E4CD8A1B2C3D4'), [
      0x01, 0x2E, 0x4C, 0xD8, 0xA1, 0xB2, 0xC3, 0xD4, //
    ]);
    expect(FelicaInputValidator.parseBytes8('00 f1:00-00 00 01 43 00'), [
      0x00,
      0xF1,
      0x00,
      0x00,
      0x00,
      0x01,
      0x43,
      0x00,
    ]);
    expect(FelicaInputValidator.parseBytes8('012E4CD8A1B2C3'), isNull);
    expect(FelicaInputValidator.parseBytes8('012E4CD8A1B2C3D4FF'), isNull);
    expect(FelicaInputValidator.parseBytes8('012E4CD8A1B2C3DG'), isNull);
    expect(FelicaInputValidator.parseBytes8(''), isNull);
  });

  test('system codes are distinct 4-digit hex values', () {
    expect(FelicaInputValidator.parseSystemCodes('0003'), [0x0003]);
    expect(FelicaInputValidator.parseSystemCodes(' 0003, fe00，88B4 '), [
      0x0003,
      0xFE00,
      0x88B4,
    ]);
    expect(FelicaInputValidator.parseSystemCodes(''), isNull);
    expect(FelicaInputValidator.parseSystemCodes('003'), isNull);
    expect(FelicaInputValidator.parseSystemCodes('0003, 0003'), isNull);
    expect(
      FelicaInputValidator.parseSystemCodes(
        List.generate(17, (i) => i.toRadixString(16).padLeft(4, '0')).join(','),
      ),
      isNull,
    );
  });
}
