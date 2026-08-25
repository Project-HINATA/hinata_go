import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../context_extensions.dart';
import '../../../../services/communication/remote_hinata_impl.dart';
import '../../../../services/notification_service.dart';

class IoConfigCard extends ConsumerStatefulWidget {
  final RemoteHinataDeviceImpl? remoteDevice;

  const IoConfigCard({
    super.key,
    required this.remoteDevice,
  });

  @override
  ConsumerState<IoConfigCard> createState() => _IoConfigCardState();
}

class _IoConfigCardState extends ConsumerState<IoConfigCard> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _ioInfo;
  Map<String, dynamic>? _ioConfig;

  // Local editable values
  String _logLevel = 'info';
  double _brightness = 255.0;
  bool _tunion = false;
  bool _autoUpdate = false;
  late TextEditingController _reportUrlController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _reportUrlController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchIoData();
    });
  }

  @override
  void didUpdateWidget(covariant IoConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteDevice != widget.remoteDevice) {
      _fetchIoData();
    }
  }

  @override
  void dispose() {
    _reportUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchIoData() async {
    final dev = widget.remoteDevice;
    if (dev == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No device connected';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final info = await dev.getIoInfo();
      final config = await dev.getIoConfig();

      if (!mounted) return;
      setState(() {
        _ioInfo = info;
        _ioConfig = config;

        _logLevel = (config['logLevel']?.toString() ?? 'info').toLowerCase();
        _brightness = double.tryParse(config['brightness']?.toString() ?? '255') ?? 255.0;
        _tunion = config['tunion']?.toString().toLowerCase() == 'true';
        _autoUpdate = config['autoUpdate']?.toString().toLowerCase() == 'true';
        _reportUrlController.text = config['reportUrl']?.toString() ?? '';

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _saveConfig() async {
    final dev = widget.remoteDevice;
    if (dev == null) return;

    final notification = ref.read(notificationServiceProvider);
    final l10n = context.l10n;

    setState(() => _isSaving = true);
    try {
      await dev.setIoConfig('logLevel', _logLevel);
      await dev.setIoConfig('brightness', _brightness.round().toString());
      await dev.setIoConfig('tunion', _tunion ? 'true' : 'false');
      await dev.setIoConfig('autoUpdate', _autoUpdate ? 'true' : 'false');
      await dev.setIoConfig('reportUrl', _reportUrlController.text.trim());

      notification.showSuccess(l10n.ioConfigSaved);
    } catch (e) {
      notification.showError('Failed to save IO config: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: context.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.ioConfig,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                  onPressed: _isLoading ? null : _fetchIoData,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              _buildErrorView(context)
            else
              _buildConfigContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: context.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.remoteDeviceOffline,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onErrorContainer,
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: _fetchIoData,
            child: Text(context.l10n.reconnect),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigContent(BuildContext context) {
    final l10n = context.l10n;
    final version = _ioInfo?['version']?.toString() ?? 'Unknown';
    final process = _ioInfo?['process']?.toString() ?? 'AimeIO';
    final backends = (_ioInfo?['backends'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // IO info header chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.memory, size: 16, color: context.colorScheme.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$process ($version)',
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.hostProcess}: $process',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (backends.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: backends.map((backend) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        backend,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Log level dropdown
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.logLevel, style: context.textTheme.bodyMedium),
            DropdownButton<String>(
              value: ['trace', 'debug', 'info', 'warn', 'error', 'off'].contains(_logLevel)
                  ? _logLevel
                  : 'info',
              items: const [
                DropdownMenuItem(value: 'trace', child: Text('Trace')),
                DropdownMenuItem(value: 'debug', child: Text('Debug')),
                DropdownMenuItem(value: 'info', child: Text('Info')),
                DropdownMenuItem(value: 'warn', child: Text('Warn')),
                DropdownMenuItem(value: 'error', child: Text('Error')),
                DropdownMenuItem(value: 'off', child: Text('Off')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _logLevel = value);
                }
              },
            ),
          ],
        ),
        const Divider(height: 16),

        // Brightness slider
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.brightness, style: context.textTheme.bodyMedium),
                Text('${_brightness.round()} / 255', style: context.textTheme.bodySmall),
              ],
            ),
            Slider(
              value: _brightness.clamp(0.0, 255.0),
              min: 0,
              max: 255,
              divisions: 255,
              label: _brightness.round().toString(),
              onChanged: (val) => setState(() => _brightness = val),
            ),
          ],
        ),
        const Divider(height: 16),

        // T-Union Switch
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.tunion),
          value: _tunion,
          onChanged: (val) => setState(() => _tunion = val),
        ),

        // Auto Update Switch
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.autoUpdate),
          value: _autoUpdate,
          onChanged: (val) => setState(() => _autoUpdate = val),
        ),
        const SizedBox(height: 8),

        // Report URL
        TextField(
          controller: _reportUrlController,
          decoration: InputDecoration(
            labelText: l10n.reportUrl,
            hintText: 'https://...',
            prefixIcon: const Icon(Icons.link, size: 20),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Save Button
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveConfig,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(l10n.saveIoConfig),
          ),
        ),
      ],
    );
  }
}
