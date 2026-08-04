import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/services/remote_crypto.dart';

void main() {
  const password = 'test-remote-password';
  const plaintext = <String, dynamic>{
    'action': 'KEY_PRESS',
    'body': {'key': 32, 'count': 1},
  };
  const messageId = '00000000-0000-4000-8000-000000000001';
  const expiresAt = 1700000000123;
  final salt = base64Url.decode('ABEiM0RVZneImaq7zN3u_w==');
  final nonce = base64Url.decode('Dw4NDAsKCQgHBgUE');

  test('decrypts the shared Rust/Dart fixture', () async {
    final envelope =
        jsonDecode('''
      {
        "action": "E2EE_V1",
        "body": {
          "salt": "ABEiM0RVZneImaq7zN3u_w",
          "nonce": "Dw4NDAsKCQgHBgUE",
          "message_id": "$messageId",
          "expires_at": $expiresAt,
          "ciphertext": "2boPibGx_ErUB0K-8w2NPYaA6IK549jlVYQcZHoi_RAolCk7w8ktNj2WuKpVNftgGxS_08ksxVs97mw5l2Y-6JVv"
        }
      }
      ''')
            as Map<String, dynamic>;

    expect(
      await RemoteCrypto.decryptMessage(password: password, envelope: envelope),
      plaintext,
    );
  });

  test('produces the shared fixture when nonce is fixed', () async {
    final envelope = await RemoteCrypto.encryptMessage(
      password: password,
      message: plaintext,
      salt: salt,
      messageId: messageId,
      expiresAt: expiresAt,
      nonce: nonce,
    );

    expect(envelope['body'], {
      'salt': 'ABEiM0RVZneImaq7zN3u_w',
      'nonce': 'Dw4NDAsKCQgHBgUE',
      'message_id': messageId,
      'expires_at': expiresAt,
      'ciphertext':
          '2boPibGx_ErUB0K-8w2NPYaA6IK549jlVYQcZHoi_RAolCk7w8ktNj2WuKpVNftgGxS_08ksxVs97mw5l2Y-6JVv',
    });
  });

  test('rejects a wrong password', () async {
    final envelope = await RemoteCrypto.encryptMessage(
      password: password,
      message: plaintext,
      salt: salt,
      messageId: messageId,
      expiresAt: expiresAt,
      nonce: nonce,
    );

    expect(
      () => RemoteCrypto.decryptMessage(
        password: 'wrong-password',
        envelope: envelope,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects tampered envelope metadata', () async {
    final envelope = await RemoteCrypto.encryptMessage(
      password: password,
      message: plaintext,
      salt: salt,
      messageId: messageId,
      expiresAt: expiresAt,
      nonce: nonce,
    );
    final tampered = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    (tampered['body'] as Map<String, dynamic>)['expires_at'] = expiresAt + 1;

    expect(
      () => RemoteCrypto.decryptMessage(password: password, envelope: tampered),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects tampered ciphertext', () async {
    final envelope = await RemoteCrypto.encryptMessage(
      password: password,
      message: plaintext,
      salt: salt,
      messageId: messageId,
      expiresAt: expiresAt,
      nonce: nonce,
    );
    final tampered = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    final body = tampered['body'] as Map<String, dynamic>;
    final ciphertext = body['ciphertext'] as String;
    body['ciphertext'] =
        '${ciphertext[0] == '2' ? '3' : '2'}${ciphertext.substring(1)}';

    expect(
      () => RemoteCrypto.decryptMessage(password: password, envelope: tampered),
      throwsA(isA<FormatException>()),
    );
  });
}
