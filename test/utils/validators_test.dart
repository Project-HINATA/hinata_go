import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/remote_instance.dart';
import 'package:hinata_go/utils/validators.dart';

void main() {
  test('adds HTTPS to HINATA IO endpoints without a scheme', () {
    expect(
      Validators.buildValidUrl(
        'aime-ws.neri.moe/example',
        InstanceType.hinataIo,
      ),
      'https://aime-ws.neri.moe/example',
    );
  });

  test('keeps an explicitly selected HTTP scheme', () {
    expect(
      Validators.buildValidUrl(
        'http://localhost:8787/example',
        InstanceType.hinataIo,
      ),
      'http://localhost:8787/example',
    );
  });
}
