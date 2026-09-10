import 'package:hinata_go/l10n/app_localizations.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hinata_go/features/arcadelink/arcadelink_machine_login_page.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform authentication cancellation stays silent and permits retry',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('moe.neri.hinatago/arcadelink_native');
        var errorCode = 'authentication_cancelled';
        var attempts = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'cards') {
              throw PlatformException(
                code: 'arcadelink_error',
                message: '请先登录',
              );
            }
            attempts++;
            throw PlatformException(
              code: errorCode,
              message: 'The operation could not be completed (1001)',
            );
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );

        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const ProviderScope(
                child: MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: Locale('zh'),
                  home: ArcadeLinkMachineLoginPage(
                    shopCode: 'shop',
                    publicId: 'machine',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('使用 Passkey 登录'), findsOneWidget);
            final labels = [
              if (platform == TargetPlatform.iOS) '使用 MuNET 登录',
              '使用 Passkey 登录',
            ];
            for (final label in labels) {
              await tester.ensureVisible(find.text(label));
              await tester.tap(find.text(label));
              await tester.pumpAndSettle();
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.text(label), findsOneWidget);
            }
            expect(attempts, labels.length);

            errorCode = 'arcadelink_error';
            await tester.tap(find.text('使用 Passkey 登录'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(attempts, labels.length + 1);
            await tester.tap(find.text('知道了'));
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            expect(request.url.path, '/api/machines/session/start');
            return http.Response(
              jsonEncode({
                'ticket': 'test',
                'expiresIn': 300,
                'machine': {
                  'publicId': 'machine',
                  'name': '舞萌',
                  'shop': {'name': '测试店铺'},
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
