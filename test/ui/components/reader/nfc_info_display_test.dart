import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/ui/components/reader/nfc_info_display.dart';

void main() {
  testWidgets('does not offer an iOS scan action when NFC is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(const NfcState(isIOS: true, status: NfcStatus.unsupported)),
    );

    final inkWell = _scanInkWell(tester, l10n.nfcUnavailable);

    expect(find.text(l10n.nfcUnavailable), findsOneWidget);
    expect(find.text(l10n.tapToScan), findsNothing);
    expect(inkWell.onTap, isNull);
    expect(inkWell.onLongPress, isNull);
  });

  testWidgets('offers an iOS scan action when NFC is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(const NfcState(isIOS: true, status: NfcStatus.tapToScan)),
    );

    final inkWell = _scanInkWell(tester, l10n.tapToScan);

    expect(find.text(l10n.tapToScan), findsOneWidget);
    expect(inkWell.onTap, isNotNull);
    expect(inkWell.onLongPress, isNotNull);
  });

  testWidgets('shows prohibited icon and inactive text when NFC is inactive', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      _buildTestApp(const NfcState(isIOS: false, status: NfcStatus.disabled)),
    );

    expect(find.text(l10n.nfcInactive), findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
  });
}

InkWell _scanInkWell(WidgetTester tester, String prompt) {
  final inkWellFinder = find.ancestor(
    of: find.text(prompt),
    matching: find.byType(InkWell),
  );
  return tester.widget<InkWell>(inkWellFinder);
}

Widget _buildTestApp(NfcState state) {
  return ProviderScope(
    overrides: [
      nfcProvider.overrideWith(() => _FixedNfcNotifier(state)),
      hardwareDeviceProvider.overrideWith(_FixedHardwareDeviceNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 240,
          child: NfcInfoDisplay(contentQuarterTurns: 0),
        ),
      ),
    ),
  );
}

class _FixedNfcNotifier extends NfcNotifier {
  _FixedNfcNotifier(this._state);

  final NfcState _state;

  @override
  NfcState build() => _state;
}

class _FixedHardwareDeviceNotifier extends HardwareDeviceNotifier {
  @override
  HardwareDeviceState build() => HardwareDeviceState();
}
