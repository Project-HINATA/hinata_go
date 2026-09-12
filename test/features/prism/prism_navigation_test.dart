import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hinata_go/features/prism/prism_machine_login_page.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/navigation/router.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/features/prism/services/prism_invocation_service.dart';
import 'package:hinata_go/ui/pages/scan_page.dart';

void main() {
  testWidgets(
    'machine return button reaches home after direct and native links',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          nfcProvider.overrideWith(_IdleNfcNotifier.new),
          hardwareDeviceProvider.overrideWith(_IdleHardwareNotifier.new),
          appUpdateProvider.overrideWith(_IdleUpdateNotifier.new),
        ],
      );
      final router = container.read(routerProvider);
      final invocation = container.read(prismInvocationProvider);
      addTearDown(() {
        router.dispose();
        invocation.clear();
        container.dispose();
      });

      await http.runWithClient(
        () async {
          router.go('https://link.neri.moe/t/shop/machine');
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

          for (var entry = 0; entry < 3; entry++) {
            if (entry == 1) router.go('/prism/shop/machine');
            if (entry == 2) {
              invocation.handleURL('https://link-beta.neri.moe/t/shop/machine');
            }
            await tester.pumpAndSettle();
            expect(find.byType(PrismMachineLoginPage), findsOneWidget);
            if (entry == 2) {
              expect(
                tester
                    .widget<PrismMachineLoginPage>(
                      find.byType(PrismMachineLoginPage),
                    )
                    .origin
                    .toString(),
                'https://link-beta.neri.moe',
              );
            }
            await tester.tap(find.byTooltip('返回主页'));
            await tester.pumpAndSettle();

            expect(router.routeInformationProvider.value.uri.path, '/scan');
            expect(find.byType(ScanPage), findsOneWidget);
            expect(find.byType(PrismMachineLoginPage), findsNothing);
            expect(find.text('Page Not Found'), findsNothing);
            expect(invocation.pendingPublicId, isNull);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () =>
            MockClient((_) async => http.Response('{"error":"offline"}', 503)),
      );
    },
  );
}

class _IdleNfcNotifier extends NfcNotifier {
  @override
  NfcState build() => const NfcState(status: NfcStatus.unsupported);
}

class _IdleHardwareNotifier extends HardwareDeviceNotifier {
  @override
  HardwareDeviceState build() => HardwareDeviceState();
}

class _IdleUpdateNotifier extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}
