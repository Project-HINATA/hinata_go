import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hinata_go/navigation/router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/features/prism/providers/prism_visit_provider.dart';
import 'package:hinata_go/features/prism/services/prism_api.dart';
import 'package:hinata_go/features/prism/prism_visit_content.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'mahjong roster uses native join/leave controls and disables full tables',
    (tester) async {
      Future<void> show(List<Map<String, dynamic>> seats) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PrismMahjongTable(
                table: {'capacity': 2, 'seats': seats},
                busy: false,
              ),
            ),
          ),
        ),
      );
      await show([
        {'name': '甲', 'mine': false, 'playing': false},
      ]);
      expect(find.text('上桌'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      await show([
        {'name': '甲', 'mine': true, 'playing': true},
      ]);
      expect(find.text('下桌'), findsOneWidget);
      expect(find.text('麻将计费中'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  const machine = PrismMachine(
    publicId: 'device',
    name: 'Device',
    shopName: 'Store',
    machineGeo: false,
    billingEnabled: true,
    webOnly: true,
    capabilities: {'door': true, 'card': true, 'coin': true, 'power': true},
    coinAfterSwipe: true,
  );
  const session = PrismMachineSession(
    ticket: 'ticket',
    expiresIn: 300,
    machine: machine,
  );

  test(
    'native QQ, entry, door, checkout and retry preserve store policy and operation IDs',
    () async {
      var member = false, active = false, checkoutAttempts = 0;
      final checkoutIds = <String>[];
      var doorCalls = 0;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
        bool requireLocation = false,
      }) async {
        if (path == '/api/v1/me') {
          return {
            'user': {'id': 'user'},
          };
        }
        if (path == '/api/v1/shops/store') {
          return {
            'shop': {
              'billingEnabled': true,
              'locationEnabled': true,
              'checkinGeo': false,
              'checkoutGeo': false,
            },
            'membership': member ? {'playerId': 'p'} : null,
            'entryPricing': [],
          };
        }
        if (path.contains('/devices/session/state')) {
          return {
            'gate': !member
                ? 'qq'
                : active
                ? 'ready'
                : 'entry',
            'power': 'unknown',
          };
        }
        if (path.endsWith('/qq-binding')) {
          return {'code': 'ABC123', 'expiresAt': '2999-01-01T00:00:00Z'};
        }
        if (path.endsWith('/session/start')) {
          expect(requireLocation, isTrue);
          expect(body?['ticket'], 'ticket');
          expect(body?['consent'], isTrue);
          active = true;
          return {};
        }
        if (path.endsWith('/player/me')) {
          return {
            'wallet': [],
            'activeSession': active
                ? {'id': 'entry', 'startedAt': '2026-09-12T00:00:00Z'}
                : null,
          };
        }
        if (path.endsWith('/player/assets')) return {'holdings': []};
        if (path.endsWith('/devices')) return {'devices': []};
        if (path.endsWith('/sessions/history')) return {'sessions': []};
        if (path.endsWith('/devices/session/actions')) {
          expect(body!['consent'], isTrue);
          expect(requireLocation, isTrue);
          doorCalls++;
          return {
            'temporaryPassword': '12345678',
            'expiresAt': '2999-01-01T00:00:00Z',
          };
        }
        if (path.endsWith('/checkout/preview')) {
          return {
            'settlementPreview': {'total': 12},
            'chargeItems': [],
            'adjustments': [],
          };
        }
        if (path.endsWith('/checkout/confirm')) {
          expect(requireLocation, isTrue);
          checkoutIds.add(body!['operationId'] as String);
          if (checkoutAttempts++ == 0) {
            throw PlatformException(
              code: 'INSUFFICIENT_BALANCE',
              message: '余额不足',
              details: {'statusCode': 400},
            );
          }
          if (checkoutAttempts == 2) {
            throw PlatformException(code: 'network_error');
          }
          if (checkoutAttempts == 3) {
            throw PlatformException(code: 'location_denied');
          }
          active = false;
          return {};
        }
        throw StateError(path);
      }

      final container = ProviderContainer(
        overrides: [prismRequestProvider.overrideWithValue(request)],
      );
      addTearDown(container.dispose);
      container.listen(prismVisitProvider, (_, _) {});
      final controller = container.read(prismVisitProvider.notifier);
      await controller.load('store', session);
      expect(container.read(prismVisitProvider).gate, 'qq');
      expect(container.read(prismVisitProvider).binding?['code'], 'ABC123');
      member = true;
      await controller.refresh();
      expect(container.read(prismVisitProvider).gate, 'entry');
      await controller.enter();
      expect(container.read(prismVisitProvider).active, isTrue);
      await controller.device('door.open', consent: true);
      expect(doorCalls, 1);
      expect(
        container.read(prismVisitProvider).password?['temporaryPassword'],
        '12345678',
      );
      controller.ticketConsumed = true;
      await controller.previewCheckout();
      expect(
        container
            .read(prismVisitProvider)
            .preview?['settlementPreview']['total'],
        12,
      );
      await controller.checkout();
      expect(container.read(prismVisitProvider).active, isTrue);
      await controller.checkout();
      await controller.checkout();
      await controller.checkout();
      expect(checkoutIds[0], isNot(checkoutIds[1]));
      expect(checkoutIds[1], checkoutIds[2]);
      expect(checkoutIds[2], checkoutIds[3]);
      expect(container.read(prismVisitProvider).active, isFalse);
      expect(container.read(prismVisitProvider).preview, isNull);
    },
  );

  test(
    'unknown HA permits nonbilling use; uncertain device requests stay blocked after reload',
    () async {
      var calls = 0;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
        bool requireLocation = false,
      }) async {
        if (path == '/api/v1/me') {
          return {
            'user': {'id': 'user'},
          };
        }
        if (path == '/api/v1/shops/store') {
          return {
            'shop': {'billingEnabled': false},
            'membership': null,
            'entryPricing': [],
          };
        }
        if (path.contains('/devices/session/state')) {
          return {'gate': 'ready', 'power': 'unknown'};
        }
        if (path.endsWith('/devices/session/actions')) {
          expect(requireLocation, isFalse);
          calls++;
          throw PlatformException(code: 'network_error');
        }
        throw StateError(path);
      }

      final container = ProviderContainer(
        overrides: [prismRequestProvider.overrideWithValue(request)],
      );
      addTearDown(container.dispose);
      container.listen(prismVisitProvider, (_, _) {});
      final controller = container.read(prismVisitProvider.notifier);
      await controller.load('store', session);
      expect(container.read(prismVisitProvider).power, 'unknown');
      expect(container.read(prismVisitProvider).billing, isFalse);
      await controller.device('coin');
      await controller.load('store', session);
      await controller.device('coin');
      expect(calls, 1);
      expect(container.read(prismVisitProvider).gate, 'expired');
    },
  );

  test(
    'late status reads cannot undo an action; expired tickets never renew',
    () async {
      final staleState = Completer<Map<String, dynamic>>();
      final staleStarted = Completer<void>();
      var reads = 0;
      var poweredOn = false;
      var expired = false;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
        bool requireLocation = false,
      }) async {
        if (path == '/api/v1/me') {
          return {
            'user': {'id': 'user'},
          };
        }
        if (path == '/api/v1/shops/store') {
          return {
            'shop': {'billingEnabled': false},
          };
        }
        if (path.contains('/devices/session/state')) {
          if (++reads == 2) {
            staleStarted.complete();
            return staleState.future;
          }
          if (expired && path.endsWith('ticket=ticket')) {
            throw PlatformException(code: 'TICKET_EXPIRED');
          }
          return {'gate': 'ready', 'power': poweredOn ? 'on' : 'off'};
        }
        if (path.endsWith('/devices/session/actions')) {
          if (expired) {
            expect(body!['ticket'], 'renewed');
          }
          poweredOn = true;
          return {};
        }
        throw StateError(path);
      }

      final container = ProviderContainer(
        overrides: [prismRequestProvider.overrideWithValue(request)],
      );
      addTearDown(container.dispose);
      container.listen(prismVisitProvider, (_, _) {});
      final controller = container.read(prismVisitProvider.notifier);
      await controller.load('store', session);
      final stale = controller.refresh();
      await staleStarted.future;
      await controller.device('power.on');
      staleState.complete({'gate': 'ready', 'power': 'off'});
      await stale;
      expect(container.read(prismVisitProvider).power, 'on');
      expired = true;
      await controller.refresh();
      expect(controller.session.ticket, 'ticket');
      expect(container.read(prismVisitProvider).gate, 'expired');
      controller.clear();
      expect(container.read(prismVisitProvider).shop, isNull);
    },
  );

  testWidgets(
    'native power, card and checkout keep spacing, pinned checkout and native navigation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var powered = false, active = true;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
        bool requireLocation = false,
      }) async {
        if (path == '/api/v1/me') {
          return {
            'user': {'id': 'user'},
          };
        }
        if (path == '/api/v1/shops/store') {
          return {
            'shop': {
              'name': 'PRiSM Store',
              'billingEnabled': true,
              'timeZone': 'Asia/Tokyo',
            },
            'membership': {'playerId': 'p'},
            'entryPricing': [],
          };
        }
        if (path.contains('/devices/session/state')) {
          return {
            'gate': active ? 'ready' : 'entry',
            'power': powered ? 'on' : 'off',
          };
        }
        if (path.endsWith('/devices/session/actions')) {
          expect(body!['action'], 'power.on');
          powered = true;
          return {};
        }
        if (path.endsWith('/player/me')) {
          return {
            'wallet': [],
            'activeSession': active
                ? {'id': 'entry', 'startedAt': '2026-09-12T00:00:00Z'}
                : null,
          };
        }
        if (path.endsWith('/player/assets')) {
          return {'holdings': []};
        }
        if (path.endsWith('/sessions/history')) {
          return {'sessions': []};
        }
        if (path.endsWith('/devices')) {
          return {'devices': []};
        }
        if (path.endsWith('/checkout/preview')) {
          return {
            'settlementPreview': {'total': 12},
            'chargeItems': List.generate(
              30,
              (index) => {'label': '费用 ${index + 1}', 'amount': .4},
            ),
            'adjustments': [],
          };
        }
        if (path.endsWith('/checkout/confirm')) {
          active = false;
          return {};
        }
        throw StateError(path);
      }

      const channel = MethodChannel('moe.neri.hinatago/prism_native');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'cards');
        return [
          {'id': 'card', 'label': 'Aime', 'accessCode': '1234'},
        ];
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final container = ProviderContainer(
        overrides: [prismRequestProvider.overrideWithValue(request)],
      );
      final router = container.read(routerProvider);
      addTearDown(() {
        router.dispose();
        container.dispose();
      });
      await http.runWithClient(
        () async {
          router.go('/prism/store/device');
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('设备尚未开机'), findsOneWidget);
          expect(
            tester.getSize(find.widgetWithText(FilledButton, '开机')).height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(find.text('开机'));
          await tester.pumpAndSettle();
          expect(find.text('投币'), findsNothing);
          final heading = find
              .ancestor(of: find.text('选择卡片'), matching: find.byType(Row))
              .first;
          expect(
            tester.getTopLeft(heading).dy -
                tester.getBottomLeft(find.byType(Card).first).dy,
            40,
          );
          await tester.tap(find.text('user'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('账单'));
          await tester.pumpAndSettle();
          expect(find.byType(PrismAccountSheet), findsOneWidget);
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.text('12.00'), findsOneWidget);
          final checkout = find.widgetWithText(FilledButton, '结账');
          expect(checkout.hitTestable(), findsOneWidget);
          final checkoutRect = tester.getRect(checkout);
          await tester.drag(
            find.ancestor(
              of: find.text('费用 1'),
              matching: find.byType(SingleChildScrollView),
            ),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(checkout), checkoutRect);
          expect(checkout.hitTestable(), findsOneWidget);
          expect(find.byType(CloseButton).hitTestable(), findsOneWidget);
          await tester.tap(find.text('结账'));
          await tester.pumpAndSettle();
          expect(active, isFalse);
          expect(find.text('已结账'), findsOneWidget);
          await tester.tap(find.byType(CloseButton));
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/prism/store/device',
          );
          // The Material menu and sheet remain usable with a keyboard on a small screen.
          tester.view.physicalSize = const Size(320, 640);
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          await tester.tap(find.text('user'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('兑换'));
          await tester.pumpAndSettle();
          final redeem = find.widgetWithText(FilledButton, '兑换');
          expect(tester.widget<FilledButton>(redeem).onPressed, isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(find.byType(TextField), 'TEST');
          await tester.pumpAndSettle();
          await tester.ensureVisible(redeem);
          await tester.pumpAndSettle();
          expect(redeem.hitTestable(), findsOneWidget);
          expect(tester.widget<FilledButton>(redeem).onPressed, isNotNull);
          expect(find.byType(CloseButton).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'ticket': 'ticket',
                'expiresIn': 300,
                'machine': {
                  'publicId': 'device',
                  'name': 'Device',
                  'coinAfterSwipe': true,
                  'capabilities': {
                    'power': true,
                    'coin': true,
                    'card': true,
                    'door': false,
                  },
                  'shop': {
                    'name': 'PRiSM Store',
                    'billingEnabled': true,
                    'machineGeo': false,
                  },
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'native auto-coin layout hides manual coin; QQ stays in the native view',
    (tester) async {
      var gate = 'qq';
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
        bool requireLocation = false,
      }) async {
        if (path == '/api/v1/me') {
          return {
            'user': {'id': 'user'},
          };
        }
        if (path == '/api/v1/shops/store') {
          return {
            'shop': {
              'billingEnabled': false,
              'botContact': 'QQ Bot',
              'autoRegister': false,
            },
            'membership': null,
            'entryPricing': [],
          };
        }
        if (path.contains('/devices/session/state')) {
          return {'gate': gate, 'power': 'unknown'};
        }
        if (path.endsWith('/qq-binding')) {
          return {'code': 'ABC123', 'expiresAt': '2999-01-01T00:00:00Z'};
        }
        throw StateError(path);
      }

      final container = ProviderContainer(
        overrides: [prismRequestProvider.overrideWithValue(request)],
      );
      addTearDown(container.dispose);
      container.listen(prismVisitProvider, (_, _) {});
      final controller = container.read(prismVisitProvider.notifier);
      await controller.load('store', session);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    PrismDeviceControls(machine: machine),
                    PrismDeviceFooter(machine: machine, cardBusy: false),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('绑定 QQ'), findsOneWidget);
      expect(find.text('生成验证码'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('prism.bind ABC123'), findsOneWidget);
      expect(find.text('在网页继续'), findsNothing);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('复制'));
      await tester.pumpAndSettle();
      expect(copied, 'prism.bind ABC123');
      gate = 'ready';
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('投币'), findsNothing);
      expect(find.text('设备尚未开机'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
