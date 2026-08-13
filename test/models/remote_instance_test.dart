import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/remote_instance.dart';

void main() {
  test('generates and persists a salt when loading a legacy instance', () {
    final instance = RemoteInstance.fromJson({
      'id': 'legacy-id',
      'name': 'Legacy',
      'icon': 'bear',
      'url': 'https://example.test/remote',
    });

    expect(instance.encryptionSalt, isNotEmpty);
    expect(instance.toJson()['encryptionSalt'], instance.encryptionSalt);
  });

  test('copyWith preserves the encryption salt', () {
    final instance = RemoteInstance(
      id: 'id',
      name: 'name',
      icon: 'bear',
      url: 'https://example.test/remote',
      encryptionSalt: 'ABEiM0RVZneImaq7zN3u_w',
    );

    expect(
      instance.copyWith(name: 'updated').encryptionSalt,
      instance.encryptionSalt,
    );
  });

  test('migrates the old HTTP public relay URL to HTTPS', () {
    final instance = RemoteInstance.fromJson({
      'id': 'legacy-id',
      'name': 'Legacy',
      'icon': 'bear',
      'url': 'http://aime-ws.neri.moe/example',
    });

    expect(instance.url, 'https://aime-ws.neri.moe/example');
  });
}
