import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hinata_go/features/prism/services/prism_api.dart';
import 'package:hinata_go/features/prism/services/prism_native_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all requests and links keep the scanned origin', () async {
    final origin = Uri.parse('https://example.com:8443');
    final paths = <String>[];
    final api = PrismAPI(
      origin: origin,
      client: MockClient((request) async {
        expect(request.url.origin, origin.origin);
        paths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': request.url.path.endsWith('/start')
                ? {
                    'ticket': 'ticket',
                    'expiresIn': 300,
                    'machine': {
                      'publicId': 'device',
                      'name': 'Device',
                      'shop': {'name': 'Shop', 'heroUrl': '/banner.png'},
                    },
                  }
                : <String, dynamic>{},
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    final session = await api.startMachineSession(
      shopCode: 'shop',
      publicId: 'device',
    );
    expect(session.machine.heroUrl, '$origin/banner.png');
    await api.cards();
    await api.loginMachine(
      cardId: 'card',
      ticket: 'ticket',
      requireLocation: false,
    );
    await api.request('/api/v1/shops/shop/player/me');
    expect(paths.length, 4);
    expect(api.munetLoginURL('ticket').origin, origin.origin);
    expect(api.webFallbackURL('ticket').origin, origin.origin);

    const channel = MethodChannel('moe.neri.hinatago/prism_native');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect((call.arguments as Map)['origin'], origin.toString());
          methods.add(call.method);
          return call.method == 'cards' ? [] : '{}';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final native = PrismNativeService(origin: origin);
    await native.authenticateWithMunet();
    await native.authenticateWithPasskey();
    await native.loadCards();
    await native.request('/api/v1/me');
    await native.loginMachine(
      cardId: 'card',
      ticket: 'ticket',
      requireLocation: false,
    );
    expect(methods.length, 5);
  });
}
