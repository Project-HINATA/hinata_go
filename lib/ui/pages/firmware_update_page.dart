import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/services/notification_service.dart';

import '../../providers/firmware_provider.dart';
import '../app_layout.dart';
import '../components/firmware/firmware_status_view.dart';

class FirmwareUpdatePage extends ConsumerWidget {
  const FirmwareUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    if (!firmwareFeatureEnabled) {
      return Scaffold(
        appBar: layout.showPageAppBar ? _buildDisabledAppBar() : null,
        body: SafeArea(
          top: !layout.showPageAppBar,
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
      child: Scaffold(
        appBar: layout.showPageAppBar
            ? _buildAppBar(context, isFlashing)
            : null,
        body: SafeArea(
          top: !layout.showPageAppBar,
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

  PreferredSizeWidget _buildDisabledAppBar() {
    return AppBar(title: const Text('Firmware Update'));
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isFlashing) {
    return AppBar(
      title: const Text('Firmware Update'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: isFlashing ? null : () => context.pop(),
      ),
    );
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
