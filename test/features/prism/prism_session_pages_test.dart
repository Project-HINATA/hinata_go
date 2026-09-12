import 'package:hinata_go/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hinata_go/features/prism/prism_machine_content.dart';
import 'package:hinata_go/features/prism/prism_machine_login_page.dart';

void main() {
  testWidgets(
    'scrolling reaches screen edges while controls keep safe insets',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const channel = MethodChannel('moe.neri.hinatago/prism_native');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => [
          for (var i = 0; i < 10; i++)
            {'id': '$i', 'label': '卡片 $i', 'accessCode': '6958'},
        ],
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await http.runWithClient(
        () async {
          for (final (size, insets) in [
            (const Size(390, 844), const EdgeInsets.only(top: 59, bottom: 34)),
            (const Size(844, 390), const EdgeInsets.fromLTRB(59, 0, 59, 21)),
          ]) {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: const Locale('zh'),
                  home: MediaQuery(
                    data: MediaQueryData(size: size, padding: insets),
                    child: const PrismMachineLoginPage(
                      shopCode: 'shop',
                      publicId: 'machine',
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final scroll = find.byType(SingleChildScrollView);
            final back = find.byTooltip('返回主页');
            final backRect = tester.getRect(back);
            expect(tester.getRect(scroll), Offset.zero & size);
            expect(backRect.top, greaterThanOrEqualTo(insets.top));
            expect(backRect.left, greaterThanOrEqualTo(insets.left));
            expect(
              tester.getTopLeft(find.byType(Card).first).dy,
              insets.top + 140,
            );

            await tester.drag(scroll, const Offset(0, -250));
            await tester.pumpAndSettle();
            expect(tester.getTopLeft(find.byType(Card).first).dy, lessThan(0));
            expect(tester.getRect(back), backRect);

            final position = tester
                .state<ScrollableState>(find.byType(Scrollable))
                .position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            expect(
              tester.getBottomRight(find.byType(Card).last).dy,
              closeTo(size.height - insets.bottom - 28, 0.01),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'ticket': 'test',
                'expiresIn': 300,
                'machine': {
                  'publicId': 'machine',
                  'name': '舞萌',
                  'shop': {'name': '测试店铺'},
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

  testWidgets('a late response cannot replace a newly invoked machine', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final oldRequest = Completer<http.Response>();
    Widget app(String id) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: PrismMachineLoginPage(shopCode: 'shop', publicId: id),
      ),
    );
    await http.runWithClient(
      () async {
        await tester.pumpWidget(app('old'));
        await tester.pump();
        expect(find.byType(PrismLoadingPage), findsOneWidget);
        await tester.pumpWidget(app('new'));
        await tester.pumpAndSettle();
        expect(find.text('新店铺'), findsOneWidget);
        oldRequest.complete(http.Response('{"error":"offline"}', 503));
        await tester.pumpAndSettle();
        expect(find.text('新店铺'), findsOneWidget);
        expect(find.byType(PrismFailurePage), findsNothing);
      },
      () => MockClient((request) async {
        if (jsonDecode(request.body)['publicId'] == 'old') {
          return oldRequest.future;
        }
        return http.Response(
          jsonEncode({
            'data': {
              'ticket': 'new',
              'expiresIn': 300,
              'machine': {
                'publicId': 'new',
                'name': '舞萌',
                'shop': {'name': '新店铺'},
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    final strings = lookupAppLocalizations(locale);
    testWidgets(
      '$locale session pages replace each other through failure, retry and terminal states',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('moe.neri.hinatago/prism_native');
        final firstRequest = Completer<http.Response>();
        final retryRequest = Completer<http.Response>();
        final firstCards = Completer<List<Object>>();
        var requests = 0;
        var cardRequests = 0;
        String? loginError = '请到店再进行登录';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'cards') {
              if (cardRequests++ == 0) return firstCards.future;
              return [
                {'id': 'card', 'label': '红黑卡', 'accessCode': '6958'},
              ];
            }
            if (loginError != null) {
              throw PlatformException(code: 'prism_error', message: loginError);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );

        http.Response session() => http.Response(
          jsonEncode({
            'data': {
              'ticket': 'test',
              'expiresIn': 300,
              'machine': {
                'publicId': 'machine',
                'name': '舞萌',
                'shop': {'name': '测试店铺'},
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

        final app = ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: PrismMachineLoginPage(shopCode: 'shop', publicId: 'machine'),
          ),
        );
        void noSessionContent() {
          expect(find.byType(PrismMachineContent), findsNothing);
          expect(find.text(strings.prismSelectCard), findsNothing);
          expect(find.text('测试店铺'), findsNothing);
          expect(find.byTooltip(strings.prismSignOut), findsNothing);
        }

        await http.runWithClient(
          () async {
            await tester.pumpWidget(app);
            await tester.pump();
            expect(find.byType(PrismLoadingPage), findsOneWidget);
            expect(find.byType(Card), findsNothing);
            noSessionContent();

            firstRequest.complete(
              http.Response(
                '{"error":"连接失败，请稍后重试"}',
                503,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(PrismFailurePage), findsOneWidget);
            expect(find.text(strings.prismSessionFailed), findsOneWidget);
            expect(find.text(strings.prismRetry), findsOneWidget);
            noSessionContent();

            await tester.tap(find.text(strings.prismRetry));
            await tester.pump();
            expect(find.byType(PrismLoadingPage), findsOneWidget);
            expect(find.text(strings.prismRetry), findsNothing);
            retryRequest.complete(session());
            await tester.pump();
            await tester.pump();
            expect(find.text('测试店铺'), findsOneWidget);
            expect(find.text(strings.prismSelectCard), findsNothing);
            firstCards.completeError(
              PlatformException(code: 'prism_error', message: '连接失败，请稍后重试'),
            );
            await tester.pumpAndSettle();
            expect(find.text(strings.prismCardsFailed), findsOneWidget);
            expect(find.text(strings.prismNoCards), findsNothing);
            await tester.tap(find.text(strings.prismRetry));
            await tester.pumpAndSettle();
            expect(find.text('红黑卡'), findsOneWidget);
            expect(find.text(strings.prismCardsFailed), findsNothing);

            await tester.tap(find.text('红黑卡'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.text(strings.prismAtArcade), findsOneWidget);
            await tester.tap(find.text(strings.prismOk));
            await tester.pumpAndSettle();
            expect(find.text(strings.prismSelectCard), findsOneWidget);

            loginError = '本次会话已失效';
            await tester.tap(find.text('红黑卡'));
            await tester.pumpAndSettle();
            expect(find.byType(PrismExpiredPage), findsOneWidget);
            expect(find.text(strings.prismExpired), findsOneWidget);
            expect(find.text(strings.prismScanAgain), findsOneWidget);
            expect(find.byType(AlertDialog), findsNothing);
            noSessionContent();

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(app);
            await tester.pumpAndSettle();
            loginError = null;
            await tester.tap(find.text('红黑卡'));
            await tester.pumpAndSettle();
            expect(find.text(strings.prismSignedIn), findsNothing);
            await tester.pump(const Duration(seconds: 3));
            expect(find.byType(PrismExpiredPage), findsOneWidget);
            noSessionContent();
            expect(tester.takeException(), isNull);
          },
          () => MockClient((request) {
            expect(request.url.path, '/api/v1/machines/session/start');
            requests++;
            return requests == 1
                ? firstRequest.future
                : requests == 2
                ? retryRequest.future
                : Future.value(session());
          }),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
