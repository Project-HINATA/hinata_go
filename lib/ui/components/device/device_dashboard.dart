import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/models/hardware_config.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';
import 'package:hinata_go/services/notification_service.dart';
import 'device_header.dart';
import 'device_settings_cards.dart';

class DeviceDashboard extends ConsumerWidget {
  final UsbHinataDeviceImpl device;
  final ScrollController? scrollController;
  const DeviceDashboard({
    required this.device,
    this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHinataLite = device.productName == "HINATA Lite";

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16.0),
      children: _buildSections(context, isHinataLite),
    );
  }

  List<Widget> _buildSections(BuildContext context, bool isHinataLite) {
    final l10n = context.l10n;

    return [
      DeviceHeader(device: device),
      const SizedBox(height: 16),
      _DashboardSection(
        title: l10n.globalSettings,
        child: GlobalSettingsCard(device: device),
      ),
      const SizedBox(height: 16),
      _DashboardSection(
        title: l10n.segaSerialSettings,
        child: SegaSettingsCard(device: device),
      ),
      if (!isHinataLite) ...[
        const SizedBox(height: 16),
        _DashboardSection(
          title: l10n.cardioSettings,
          child: CardIOSettingsCard(device: device),
        ),
      ],
      if (firmwareFeatureEnabled) ...[
        const SizedBox(height: 16),
        _DashboardSection(
          title: l10n.firmwareUpdate,
          child: _buildSettingsSection(context),
        ),
      ],
      const SizedBox(height: 24),
      _SaveToFlashButton(device: device),
      const SizedBox(height: 16),
      const _DashboardTips(),
      const SizedBox(height: 32),
    ];
  }

  Widget _buildSettingsSection(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _DashboardSettingsTile(
        icon: Icons.system_update_alt,
        title: l10n.firmwareUpdate,
        subtitle: l10n.checkLatestSoftware,
        onTap: () => context.push('/device_hub/firmware'),
      ),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            title,
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SaveToFlashButton extends ConsumerWidget {
  final UsbHinataDeviceImpl device;
  const _SaveToFlashButton({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return _DashboardActionRow(
      leading: FilledButton.tonal(
        onPressed: () => _restoreDefaults(context, ref),
        child: Text(l10n.restoreDefaults),
      ),
      trailing: FilledButton.icon(
        onPressed: () => _applySettings(context, ref),
        icon: const Icon(Icons.save),
        label: Text(l10n.applySettings),
      ),
    );
  }

  Future<void> _restoreDefaults(BuildContext context, WidgetRef ref) async {
    _showBlockingLoader(context);
    try {
      final config0 = device.config0;
      config0.segaHwFw = false;
      config0.segaFastRead = false;
      config0.serialDescriptorUnique = false;
      config0.cardioDisableIso14443a = false;
      config0.cardioIso14443aStartWithE004 = false;
      config0.enableLedRainbow = true;
      device.segaBrightness = 255;
      device.idleRGB = Colors.blue;
      device.busyRGB = Colors.green;
      await device.setConfig(ConfigIndex.config0.toInt(), config0.asByte());
      await device.setLed(device.idleRGB);

      if (context.mounted) {
        _closeBlockingLoader(context);
        ref
            .read(notificationServiceProvider)
            .showInfo('Defaults restored in RAM (Apply to flash)');
      }
    } catch (_) {
      if (context.mounted) {
        _closeBlockingLoader(context);
      }
    }
  }

  Future<void> _applySettings(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    _showBlockingLoader(context);

    try {
      await device.setStorage(ConfigIndex.config0, device.config0.asByte());
      await device.setStorage(
        ConfigIndex.segaBrightness,
        device.segaBrightness,
      );
      await device.setStorage(
        ConfigIndex.idleR,
        (device.idleRGB.r * 255).round(),
      );
      await device.setStorage(
        ConfigIndex.idleG,
        (device.idleRGB.g * 255).round(),
      );
      await device.setStorage(
        ConfigIndex.idleB,
        (device.idleRGB.b * 255).round(),
      );

      if (context.mounted) {
        _closeBlockingLoader(context);
        ref
            .read(notificationServiceProvider)
            .showSuccess(l10n.configSavedSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        _closeBlockingLoader(context);
        ref
            .read(notificationServiceProvider)
            .showError(l10n.errorSavingFlash(e.toString()));
      }
    }
  }

  void _showBlockingLoader(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _closeBlockingLoader(BuildContext context) {
    context.rootNavigator.pop();
  }
}

class _DashboardTips extends StatelessWidget {
  const _DashboardTips();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.tipsTitle, style: context.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.flashWarning, style: context.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(l10n.usbDescriptorNote, style: context.textTheme.bodyMedium),
      ],
    );
  }
}

class _DashboardSettingsTile extends StatelessWidget {
  const _DashboardSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DashboardActionRow extends StatelessWidget {
  const _DashboardActionRow({required this.leading, required this.trailing});

  final Widget leading;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [leading, const SizedBox(width: 16), trailing],
    );
  }
}
