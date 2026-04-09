import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../providers/hardware_device_provider.dart';

class DisconnectedState extends ConsumerWidget {
  final ScrollController? scrollController;

  const DisconnectedState({this.scrollController, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hardwareDeviceProvider);
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.usb_off_rounded,
                      size: 100,
                      color: context.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.noDeviceConnected,
                      style: context.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.scanForDevices,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (state.isConnecting)
                      const CircularProgressIndicator()
                    else
                      FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(hardwareDeviceProvider.notifier)
                              .requestUsbDevice();
                        },
                        icon: const Icon(Icons.search),
                        label: Text(l10n.scanUsbDevice),
                      ),
                    if (state.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
