import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/tunion.dart';
import 'package:hinata_go/models/remote_instance.dart';
import 'package:hinata_go/services/api_service.dart';
import 'package:hinata_go/services/remote_crypto.dart';
import 'package:http/http.dart' as http;

class RecordingClient extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      200,
      request: request,
    );
  }
}

void main() {
  final card = Aime(
    Uint8List.fromList([1, 2, 3, 4]),
    0x08,
    0x0004,
    Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
  );

  test('sends a V2 card body when password is empty', () async {
    final client = RecordingClient();
    final instance = RemoteInstance(
      id: 'id',
      name: 'name',
      icon: 'bear',
      url: 'https://example.test/remote',
    );

    final result = await ApiService(
      httpClient: client,
    ).sendCardData(instance: instance, card: card);

    expect(result.success, isTrue);
    expect(jsonDecode((client.request! as http.Request).body), {
      'action': 'SET_CARD_V2',
      'body': {
        'card': {
          'type': 'aime',
          'id': '01020304',
          'sak': 8,
          'atqa': 4,
          'accessCode': '00010203040506070809',
        },
      },
    });
  });

  test('sends a T-Union model without a legacy game payload', () async {
    final client = RecordingClient();
    final instance = RemoteInstance(
      id: 'id',
      name: 'name',
      icon: 'bear',
      url: 'https://example.test/remote',
    );
    final tunion = TUnion(
      Uint8List.fromList([1, 2, 3, 4]),
      0x20,
      0x0400,
      cardNumber: '01234567890123456789',
      balance: 0,
      transactions: const [],
    );

    final result = await ApiService(
      httpClient: client,
    ).sendCardData(instance: instance, card: tunion);

    expect(result.success, isTrue);
    final request = jsonDecode((client.request! as http.Request).body);
    expect(request['action'], 'SET_CARD_V2');
    expect(request['body']['card']['type'], 'tunion');
    expect(request['body']['card']['cardNumber'], '01234567890123456789');
  });

  test(
    'sends an encrypted SET_CARD body when password is configured',
    () async {
      final client = RecordingClient();
      final instance = RemoteInstance(
        id: 'id',
        name: 'name',
        icon: 'bear',
        url: 'https://example.test/remote',
        password: 'test-remote-password',
        encryptionSalt: 'ABEiM0RVZneImaq7zN3u_w',
      );

      final result = await ApiService(
        httpClient: client,
      ).sendCardData(instance: instance, card: card);

      final envelope =
          jsonDecode((client.request! as http.Request).body)
              as Map<String, dynamic>;
      final message = await RemoteCrypto.decryptMessage(
        password: instance.password,
        envelope: envelope,
      );

      expect(result.success, isTrue);
      expect(envelope['action'], 'E2EE_V1');
      expect(message['action'], 'SET_CARD_V2');
      expect(message['body'], {
        'card': {
          'type': 'aime',
          'id': '01020304',
          'sak': 8,
          'atqa': 4,
          'accessCode': '00010203040506070809',
        },
      });
    },
  );
}
