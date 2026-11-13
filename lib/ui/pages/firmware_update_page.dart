import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/providers/firmware_provider.dart';
import 'package:hinata_go/providers/hardware_device_provider.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/services/notification_service.dart';

import '../components/firmware/firmware_status_view.dart';
import '../widgets/app_scaffold.dart';

class FirmwareUpdatePage extends HookConsumerWidget {
  const FirmwareUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pause reader and phone NFC polling while the firmware update page is open.
    useEffect(() {
      final hardware = ref.read(hardwareDeviceProvider.notifier);
      final nfc = ref.read(nfcProvider.notifier);
      Future.microtask(() {
        unawaited(hardware.suspendNfcPolling());
        unawaited(nfc.suspendForExclusiveOperation());
      });
      return () => Future.microtask(() {
        hardware.resumeNfcPolling();
        nfc.resumeAfterExclusiveOperation();
      });
    }, const []);

    final l10n = context.l10n;

    if (!firmwareFeatureEnabled) {
      return AppScaffold(
        title: l10n.firmwareUpdate,
        body: SafeArea(
          top: useCupertinoChrome,
          bottom: false,
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('Firmware updates are not available in this build.'),
            ),
          ),
        ),
      );
    }

    final firmState = ref.watch(firmwareProvider);
    final isFlashing = firmState.isFlashing;

    return PopScope(
      canPop: !isFlashing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isFlashing) {
          _showFlashWarning(context, ref);
        }
      },
      child: AppScaffold(
        title: l10n.firmwareUpdate,
        nativeLeading: isFlashing ? null : NativeToolbarLeading.close,
        onNativeLeadingTap: isFlashing ? null : () => context.pop(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: isFlashing ? null : () => context.pop(),
        ),
        body: SafeArea(
          top: useCupertinoChrome,
          bottom: false,
          child: const FirmwareStatusView(),
        ),
      ),
    );
  }

  void _showFlashWarning(BuildContext context, WidgetRef ref) {
    ref
        .read(notificationServiceProvider)
        .showInfo(context.l10n.firmwareUpdateBusyWarning);
  }
}
