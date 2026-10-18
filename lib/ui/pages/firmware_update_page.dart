import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/services/notification_service.dart';

import '../../providers/firmware_provider.dart';
import '../components/firmware/firmware_status_view.dart';
import '../widgets/app_scaffold.dart';

class FirmwareUpdatePage extends ConsumerWidget {
  const FirmwareUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!firmwareFeatureEnabled) {
      return AppScaffold(
        title: 'Firmware Update',
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
        title: 'Firmware Update',
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: isFlashing ? null : () => context.pop(),
        ),
        body: SafeArea(
          top: useCupertinoChrome,
          bottom: false,
          child: _buildBody(),
        ),
      ),
    );
  }

  void _showFlashWarning(BuildContext context, WidgetRef ref) {
    ref
        .read(notificationServiceProvider)
        .showInfo('Please wait until firmware update is complete.');
  }

  Widget _buildBody() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: FirmwareStatusView(),
      ),
    );
  }
}
