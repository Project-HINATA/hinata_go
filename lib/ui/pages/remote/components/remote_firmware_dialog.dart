import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../context_extensions.dart';
import '../../../../services/communication/remote_hinata_impl.dart';

class RemoteFirmwareDialog extends StatefulWidget {
  final RemoteHinataDeviceImpl remoteDevice;

  const RemoteFirmwareDialog({
    super.key,
    required this.remoteDevice,
  });

  @override
  State<RemoteFirmwareDialog> createState() => _RemoteFirmwareDialogState();
}

enum _FirmwareDialogState {
  checking,
  checked,
  updating,
  completed,
  error,
}

class _RemoteFirmwareDialogState extends State<RemoteFirmwareDialog> {
  _FirmwareDialogState _dialogState = _FirmwareDialogState.checking;
  String? _errorMessage;

  Map<String, dynamic>? _checkResult;
  String? _latestVersion;
  String? _changelog;
  bool _hasUpdate = false;

  double _progress = 0.0;
  String _progressStage = '';
  String _progressMessage = '';
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void initState() {
    super.initState();
    _checkFirmware();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _checkFirmware() async {
    setState(() {
      _dialogState = _FirmwareDialogState.checking;
      _errorMessage = null;
    });

    try {
      final result = await widget.remoteDevice.checkFirmware(channel: 'latest');
      if (!mounted) return;

      final hasUpdate = result['has_update'] == true || result['hasUpdate'] == true;
      final latestVer = result['latest_version']?.toString() ??
          result['latestVersion']?.toString() ??
          result['version']?.toString();
      final changelog = result['changelog']?.toString() ?? result['release_notes']?.toString();

      setState(() {
        _checkResult = result;
        _hasUpdate = hasUpdate;
        _latestVersion = latestVer;
        _changelog = changelog;
        _dialogState = _FirmwareDialogState.checked;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _dialogState = _FirmwareDialogState.error;
      });
    }
  }

  Future<void> _startUpdate() async {
    setState(() {
      _dialogState = _FirmwareDialogState.updating;
      _progress = 0.0;
      _progressStage = 'starting';
      _progressMessage = context.l10n.startingUpdate;
      _errorMessage = null;
    });

    // Subscribe to progress events
    await _progressSub?.cancel();
    _progressSub = widget.remoteDevice.firmwareProgressStream.listen(
      (event) {
        if (!mounted) return;
        final stage = event['stage']?.toString() ?? '';
        final progressVal = (event['progress'] as num?)?.toDouble() ?? _progress;
        final message = event['message']?.toString() ?? '';

        setState(() {
          _progressStage = stage;
          _progress = progressVal.clamp(0.0, 100.0);
          _progressMessage = message.isNotEmpty ? message : stage;

          if (stage == 'complete' || stage == 'completed' || _progress >= 100.0) {
            _dialogState = _FirmwareDialogState.completed;
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = err.toString();
          _dialogState = _FirmwareDialogState.error;
        });
      },
    );

    try {
      await widget.remoteDevice.startFirmwareUpdate(channel: 'latest');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _dialogState = _FirmwareDialogState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: context.colorScheme.primary),
          const SizedBox(width: 8),
          Text(l10n.firmwareUpdate),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: switch (_dialogState) {
            _FirmwareDialogState.checking => _buildCheckingContent(context),
            _FirmwareDialogState.checked => _buildCheckedContent(context),
            _FirmwareDialogState.updating => _buildUpdatingContent(context),
            _FirmwareDialogState.completed => _buildCompletedContent(context),
            _FirmwareDialogState.error => _buildErrorContent(context),
          },
        ),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildCheckingContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(context.l10n.checkingUpdate, style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildCheckedContent(BuildContext context) {
    final l10n = context.l10n;

    if (!_hasUpdate) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 12),
          Text(
            l10n.firmwareUpToDate,
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (_latestVersion != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.latestVersion(_latestVersion!),
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.new_releases, color: context.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newFirmwareFound(_latestVersion ?? 'latest'),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_changelog != null && _changelog!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.changelog,
            style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _changelog!,
              style: context.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUpdatingContent(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.updateInProgress,
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _progress > 0 ? _progress / 100.0 : null,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _progressMessage,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${_progress.round()}%',
              style: context.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedContent(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.task_alt, size: 56, color: Colors.green),
        const SizedBox(height: 12),
        Text(
          l10n.updateCompleted,
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildErrorContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: context.colorScheme.error),
        const SizedBox(height: 12),
        Text(
          _errorMessage ?? context.l10n.failedToCheckFirmware,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.error,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final l10n = context.l10n;

    switch (_dialogState) {
      case _FirmwareDialogState.checking:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ];

      case _FirmwareDialogState.checked:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          if (_hasUpdate)
            FilledButton.icon(
              onPressed: _startUpdate,
              icon: const Icon(Icons.download, size: 18),
              label: Text(l10n.startUpdate),
            )
          else
            FilledButton.tonal(
              onPressed: _startUpdate, // Allows force update
              child: Text(l10n.retryUpdate),
            ),
        ];

      case _FirmwareDialogState.updating:
        return const []; // Non-dismissible while flashing

      case _FirmwareDialogState.completed:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ];

      case _FirmwareDialogState.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _checkFirmware,
            child: Text(l10n.retryUpdate),
          ),
        ];
    }
  }
}
