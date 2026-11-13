import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/firmware_provider.dart';
import '../../../providers/hardware_device_provider.dart';

class FirmwareStatusView extends ConsumerWidget {
  const FirmwareStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (!firmwareFeatureEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Firmware updates are not available in this build.',
            style: context.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final firmState = ref.watch(firmwareProvider);
    final flashNotifier = ref.read(firmwareProvider.notifier);
    final deviceState = ref.watch(hardwareDeviceProvider);
    final device = deviceState.connectedDevice;
    final firmware = firmState.firmware;

    if (firmState.isRequesting) {
      return const _LoadingState();
    }

    if (firmState.status != FirmwareUpdateStatus.idle) {
      return _UpdatingCard(
        state: firmState,
        onRetry: device != null ? () => flashNotifier.startFlash(device) : null,
      );
    }

    if (device == null) {
      return const _EmptyState();
    }

    void onChannelChanged(String channel) {
      flashNotifier.setChannel(channel, device);
    }

    if (firmState.hasFetchError || firmware == null) {
      return _FetchErrorState(
        channel: firmState.channel,
        onChannelChanged: onChannelChanged,
        onRetry: () => flashNotifier.requestFirmware(device),
      );
    }

    final isLatest = firmware.isLatest ?? false;
    final displayVersion = isLatest
        ? (deviceState.firmwareVersion ?? firmware.version ?? '—')
        : (firmware.version ?? '—');
    final isWindowsWeb =
        kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    return _VersionCard(
      firmwareVersion: displayVersion,
      channel: firmState.channel,
      onChannelChanged: onChannelChanged,
      changelog: firmware.message,
      isLatest: isLatest,
      onInstall: isWindowsWeb ? null : () => flashNotifier.startFlash(device),
      windowsWebNotice: !isLatest && isWindowsWeb
          ? _buildWindowsWebNotice(context, l10n)
          : null,
    );
  }

  Widget _buildWindowsWebNotice(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.windowsFirmwareUpdateUnavailable,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(
                'https://github.com/Project-HINATA/hinata_client-pub/releases/latest',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.openHinataClient),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return _BaseCard(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.usb_off_rounded,
            size: 48,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          l10n.firmwareUpdateUnconnectedTitle,
          textAlign: TextAlign.center,
          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.firmwareUpdateUnconnectedSubtitle,
          textAlign: TextAlign.center,
          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FetchErrorState extends StatelessWidget {
  final String channel;
  final ValueChanged<String> onChannelChanged;
  final VoidCallback onRetry;

  const _FetchErrorState({
    required this.channel,
    required this.onChannelChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return _BaseCard(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: cs.onErrorContainer,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          l10n.firmwareUpdateFetchErrorTitle,
          textAlign: TextAlign.center,
          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.firmwareUpdateFetchErrorSubtitle,
          textAlign: TextAlign.center,
          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        _ChannelSelector(channel: channel, onChanged: onChannelChanged),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.retryUpdate),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: cs.primary),
          const SizedBox(height: 24),
          Text(
            context.l10n.firmwareUpdateLoadingText,
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final String firmwareVersion;
  final String channel;
  final ValueChanged<String> onChannelChanged;
  final String? changelog;
  final bool isLatest;
  final VoidCallback? onInstall;
  final Widget? windowsWebNotice;

  const _VersionCard({
    required this.firmwareVersion,
    required this.channel,
    required this.onChannelChanged,
    this.changelog,
    this.isLatest = false,
    this.onInstall,
    this.windowsWebNotice,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final hasChangelog = changelog != null && changelog!.isNotEmpty;

    return _ScrollableBaseCard(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.firmwareUpdateVersionHeader,
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  firmwareVersion,
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            _ChannelSelector(channel: channel, onChanged: onChannelChanged),
          ],
        ),
        const SizedBox(height: 24),
        Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        if (isLatest)
          _buildLatestBadge(cs, tt, l10n.firmwareUpdateLatestBadge)
        else if (hasChangelog)
          _buildChangelog(cs, tt, l10n.firmwareUpdateChangelogTitle),
        if (!isLatest) ...[
          const SizedBox(height: 28),
          if (windowsWebNotice != null)
            windowsWebNotice!
          else if (onInstall != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.system_update_alt_rounded),
                label: Text(l10n.firmwareUpdateInstallButton),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildLatestBadge(ColorScheme cs, TextTheme tt, String badge) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 40, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            badge,
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangelog(ColorScheme cs, TextTheme tt, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            changelog!,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdatingCard extends StatelessWidget {
  final FirmwareState state;
  final VoidCallback? onRetry;

  const _UpdatingCard({required this.state, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;

    final String message = switch (state.status) {
      FirmwareUpdateStatus.success => l10n.firmwareUpdateSuccessMessage,
      FirmwareUpdateStatus.error =>
        state.flashError != null
            ? '${state.statusText}: ${state.flashError}'
            : state.statusText,
      _ => state.statusText,
    };

    return _BaseCard(
      children: [
        if (state.status == FirmwareUpdateStatus.updating) ...[
          CircularProgressIndicator(
            value: state.progress > 0 ? state.progress : null,
            color: cs.primary,
          ),
          const SizedBox(height: 32),
        ] else ...[
          Icon(
            state.status == FirmwareUpdateStatus.success
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 64,
            color: state.status == FirmwareUpdateStatus.success
                ? Colors.green
                : cs.error,
          ),
          const SizedBox(height: 32),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (state.status == FirmwareUpdateStatus.error && onRetry != null) ...[
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retryUpdate),
          ),
        ],
      ],
    );
  }
}

class _BaseCard extends StatelessWidget {
  final List<Widget> children;

  const _BaseCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          padding: const EdgeInsets.all(36),
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _ScrollableBaseCard extends StatelessWidget {
  final List<Widget> children;

  const _ScrollableBaseCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelSelector extends StatelessWidget {
  final String channel;
  final ValueChanged<String> onChanged;

  const _ChannelSelector({required this.channel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment<String>(
          value: 'stable',
          label: Text(l10n.firmwareUpdateChannelStable),
        ),
        ButtonSegment<String>(
          value: 'canary',
          label: Text(l10n.firmwareUpdateChannelCanary),
        ),
      ],
      selected: {channel},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) {
          onChanged(selected.first);
        }
      },
    );
  }
}
