import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class RemoteCrypto {
  static const _envelopeAction = 'E2EE_V1';
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _pbkdf2Iterations = 600000;
  static const _keyBits = 256;

  static final _cipher = AesGcm.with256bits();
  static final _keyDerivation = Pbkdf2.hmacSha256(
    iterations: _pbkdf2Iterations,
    bits: _keyBits,
  );
  static final _keyCache = <String, Future<SecretKey>>{};

  static String generateSalt() {
    return _encodeBase64Url(_randomBytes(_saltLength));
  }

  static List<int> decodeSalt(String encodedSalt) {
    return _decodeBase64Url('salt', encodedSalt, _saltLength);
  }

  static Future<Map<String, dynamic>> encryptMessage({
    required String password,
    required Map<String, dynamic> message,
    required List<int> salt,
    required String messageId,
    int? expiresAt,
    List<int>? nonce,
  }) async {
    _validatePasswordAndMessageId(password, messageId);
    _validateLength('salt', salt, _saltLength);

    final encodedSalt = _encodeBase64Url(salt);
    final nonceBytes = nonce ?? _randomBytes(_nonceLength);
    _validateLength('nonce', nonceBytes, _nonceLength);
    final aad = _buildAad(encodedSalt, messageId, expiresAt);
    final secretKey = await _deriveKey(password, encodedSalt, salt);
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(message)),
      secretKey: secretKey,
      nonce: nonceBytes,
      aad: aad,
    );
    final ciphertext = <int>[...secretBox.cipherText, ...secretBox.mac.bytes];

    return {
      'action': _envelopeAction,
      'body': {
        'salt': encodedSalt,
        'nonce': _encodeBase64Url(nonceBytes),
        'message_id': messageId,
        'expires_at': expiresAt,
        'ciphertext': _encodeBase64Url(ciphertext),
      },
    };
  }

  static Future<Map<String, dynamic>> decryptMessage({
    required String password,
    required Map<String, dynamic> envelope,
  }) async {
    final action = envelope['action'];
    if (action != _envelopeAction) {
      throw const FormatException('Invalid remote encryption action');
    }
    _validateNonEmptyPassword(password);

    final bodyValue = envelope['body'];
    if (bodyValue is! Map) {
      throw const FormatException('Invalid remote encryption body');
    }
    final body = Map<String, dynamic>.from(bodyValue);
    final saltValue = body['salt'];
    final nonceValue = body['nonce'];
    final messageIdValue = body['message_id'];
    final ciphertextValue = body['ciphertext'];
    if (saltValue is! String ||
        nonceValue is! String ||
        messageIdValue is! String ||
        ciphertextValue is! String) {
      throw const FormatException('Invalid remote encryption fields');
    }
    _validateNonEmptyMessageId(messageIdValue);

    final expiresAt = body['expires_at'];
    if (expiresAt != null && expiresAt is! int) {
      throw const FormatException('Invalid remote encryption expiration');
    }
    final salt = _decodeBase64Url('salt', saltValue, _saltLength);
    final nonce = _decodeBase64Url('nonce', nonceValue, _nonceLength);
    final combinedCiphertext = _decodeBase64Url(
      'ciphertext',
      ciphertextValue,
      _macLength + 1,
    );
    final ciphertext = combinedCiphertext.sublist(
      0,
      combinedCiphertext.length - _macLength,
    );
    final mac = Mac(
      combinedCiphertext.sublist(combinedCiphertext.length - _macLength),
    );
    final aad = _buildAad(saltValue, messageIdValue, expiresAt as int?);
    final secretKey = await _deriveKey(password, saltValue, salt);

    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: secretKey,
        aad: aad,
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map) {
        throw const FormatException('Invalid decrypted remote message');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const FormatException('Remote encryption authentication failed');
    }
  }

  static Future<SecretKey> _deriveKey(
    String password,
    String encodedSalt,
    List<int> salt,
  ) async {
    final cacheKey = '$password\u0000$encodedSalt';
    final future = _keyCache.putIfAbsent(
      cacheKey,
      () =>
          _keyDerivation.deriveKeyFromPassword(password: password, nonce: salt),
    );
    try {
      return await future;
    } catch (_) {
      _keyCache.remove(cacheKey);
      rethrow;
    }
  }

  static List<int> _buildAad(
    String encodedSalt,
    String messageId,
    int? expiresAt,
  ) {
    return utf8.encode(
      'aimeio-remote-e2ee-v1\n$encodedSalt\n$messageId\n${expiresAt ?? ''}',
    );
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static String _encodeBase64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static List<int> _decodeBase64Url(
    String field,
    String value,
    int minimumLength,
  ) {
    if (value.contains('=')) {
      throw FormatException('Invalid base64url in $field');
    }
    final padding = (4 - value.length % 4) % 4;
    final paddedValue = value.padRight(value.length + padding, '=');
    final decoded = <int>[];
    try {
      decoded.addAll(base64Url.decode(paddedValue));
    } catch (_) {
      throw FormatException('Invalid base64url in $field');
    }
    if (_encodeBase64Url(decoded) != value || decoded.length < minimumLength) {
      throw FormatException('Invalid $field length or encoding');
    }
    return decoded;
  }

  static void _validatePasswordAndMessageId(String password, String messageId) {
    _validateNonEmptyPassword(password);
    _validateNonEmptyMessageId(messageId);
  }

  static void _validateNonEmptyPassword(String password) {
    if (password.isEmpty) {
      throw const FormatException('Remote encryption password is empty');
    }
  }

  static void _validateNonEmptyMessageId(String messageId) {
    if (messageId.isEmpty) {
      throw const FormatException('Remote encryption message id is empty');
    }
  }

  static void _validateLength(String field, List<int> value, int expected) {
    if (value.length != expected) {
      throw FormatException('Invalid $field length');
    }
  }
}
