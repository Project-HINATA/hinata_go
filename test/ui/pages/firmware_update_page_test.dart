import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/providers/firmware_provider.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/services/reader/usb_hinata_impl.dart';
import 'package:hinata_go/ui/components/device/device_dashboard.dart';
import 'package:hinata_go/ui/components/device/device_mini_bar.dart';
import 'package:hinata_go/ui/pages/firmware_update_page.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeFirmwareNotifier extends FirmwareNotifier {
  final FirmwareState initial;
  final List<String> requestedChannels = [];

  _FakeFirmwareNotifier(this.initial);

  @override
  FirmwareState build() => initial;

  @override
  Future<void> setChannel(String channel, UsbHinataDeviceImpl? device) async {
    state = state.copyWith(channel: channel);
    requestedChannels.add(channel);
  }
}

class _FakeHardwareDeviceNotifier extends HardwareDeviceNotifier {
  final HardwareDeviceState initial;

  _FakeHardwareDeviceNotifier(this.initial);

  @override
  HardwareDeviceState build() => initial;
}

class _DummyHidDevice implements HIDDevice {
  @override
  List<HIDCollectionInfo> get collections => const [];

  @override
  bool get opened => true;

  @override
  int get productId => 0x0148;

  @override
  String get productName => 'HINATA Lite';

  @override
  int get vendorId => 0xF822;

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  void onInputReport(Function(HIDInputReportEvent)? callback) {}

  @override
  Future<void> sendReport(int reportId, ByteData data) async {}
}

UsbHinataDeviceImpl _dummyDevice() =>
    UsbHinataDeviceImpl(HinataReader(_DummyHidDevice()));

Widget _wrapWithLocale(
  Widget child, {
  Locale locale = const Locale('zh'),
  List<dynamic> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  test('FirmwareState defaults to stable channel and computes hasUpdate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = container.read(firmwareProvider);
    expect(initial.channel, 'stable');
    expect(initial.hasUpdate, isFalse);

    final withUpdate = FirmwareState(
      firmware: FirmwareReleaseInfo(isLatest: false, version: '20261113'),
      hasBadgeUpdate: true,
    );
    expect(withUpdate.hasUpdate, firmwareFeatureEnabled);

    final upToDate = FirmwareState(
      firmware: FirmwareReleaseInfo(isLatest: true, version: '20261113'),
      hasBadgeUpdate: false,
    );
    expect(upToDate.hasUpdate, isFalse);
  });

  testWidgets(
    'FirmwareUpdatePage suspends reader polling while open and resumes on close',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FirmwareUpdatePage(),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(hardwareDeviceProvider).isNfcPollingSuspended,
        isTrue,
      );

      // Navigate away / unmount FirmwareUpdatePage
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      expect(
        container.read(hardwareDeviceProvider).isNfcPollingSuspended,
        isFalse,
      );
    },
  );

  testWidgets(
    'FirmwareUpdatePage shows card UI and allows selecting stable or canary',
    (tester) async {
      final device = _dummyDevice();
      final notifier = _FakeFirmwareNotifier(
        FirmwareState(
          firmware: FirmwareReleaseInfo(
            isLatest: false,
            version: '20261113-abc',
            message: 'Fix UART deadlock',
          ),
        ),
      );

      await tester.pumpWidget(
        _wrapWithLocale(
          const FirmwareUpdatePage(),
          overrides: [
            firmwareProvider.overrideWith(() => notifier),
            hardwareDeviceProvider.overrideWith(
              () => _FakeHardwareDeviceNotifier(
                HardwareDeviceState(
                  connectedDevice: device,
                  firmwareVersion: '20261101-old',
                  productId: 0x0148,
                  hidAvailable: true,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('20261113-abc'), findsOneWidget);
      expect(find.text('Fix UART deadlock'), findsOneWidget);
      expect(find.text('Stable'), findsOneWidget);
      expect(find.text('Canary'), findsOneWidget);

      await tester.tap(find.text('Canary'));
      await tester.pumpAndSettle();
      expect(notifier.requestedChannels, ['canary']);
    },
  );

  testWidgets(
    'DeviceMiniBar and DeviceDashboard show badge and subtitle when update available',
    (tester) async {
      final device = _dummyDevice();
      final firmState = FirmwareState(
        firmware: FirmwareReleaseInfo(
          isLatest: false,
          version: '20261113-abc',
          message: 'New release',
        ),
        hasBadgeUpdate: true,
      );
      final devState = HardwareDeviceState(
        connectedDevice: device,
        firmwareVersion: '20261101-old',
        productId: 0x0148,
        hidAvailable: true,
      );

      await tester.pumpWidget(
        _wrapWithLocale(
          Column(
            children: [
              const DeviceMiniBar(),
              Expanded(child: DeviceDashboard(device: device)),
            ],
          ),
          overrides: [
            firmwareProvider.overrideWith(
              () => _FakeFirmwareNotifier(firmState),
            ),
            hardwareDeviceProvider.overrideWith(
              () => _FakeHardwareDeviceNotifier(devState),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // DeviceMiniBar renders a visible badge immediately.
      expect(
        tester
            .widgetList<Badge>(find.byType(Badge))
            .where((b) => b.isLabelVisible)
            .length,
        1,
      );

      // Scroll DeviceDashboard down to bring the firmware update tile into view.
      await tester.scrollUntilVisible(
        find.text('有新固件'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final badges = tester.widgetList<Badge>(find.byType(Badge));
      expect(
        badges.where((b) => b.isLabelVisible).length,
        greaterThanOrEqualTo(2),
      );
      expect(find.text('有新固件'), findsOneWidget);
    },
  );
}
