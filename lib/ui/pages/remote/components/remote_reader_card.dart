import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../context_extensions.dart';
import '../../../../services/communication/remote_hinata_impl.dart';
import '../../../../services/notification_service.dart';
import 'remote_firmware_dialog.dart';

class RemoteReaderCard extends ConsumerStatefulWidget {
  final RemoteHinataDeviceImpl? remoteDevice;

  const RemoteReaderCard({
    super.key,
    required this.remoteDevice,
  });

  @override
  ConsumerState<RemoteReaderCard> createState() => _RemoteReaderCardState();
}

class _RemoteReaderCardState extends ConsumerState<RemoteReaderCard> {
  bool _isLoading = true;
  String? _errorMessage;

  int? _firmwareTimestamp;
  List<int>? _chipId;
  int? _productId;
  Config0 _config0 = Config0();
  Color _idleColor = Colors.blue;
  Color _busyColor = Colors.green;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchHardwareInfo();
    });
  }

  @override
  void didUpdateWidget(covariant RemoteReaderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteDevice != widget.remoteDevice) {
      _fetchHardwareInfo();
    }
  }

  Future<void> _fetchHardwareInfo() async {
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
      final timestamp = await dev.getFirmTimeStamp();
      final chipId = await dev.getChipId();

      // Read config0
      final config0Byte = await dev.getConfig(ConfigIndex.config0.toInt());
      final config0 = Config0.fromByte(config0Byte);

      // Read colors
      final r = await dev.getConfig(ConfigIndex.idleR.toInt());
      final g = await dev.getConfig(ConfigIndex.idleG.toInt());
      final b = await dev.getConfig(ConfigIndex.idleB.toInt());
      final br = await dev.getConfig(ConfigIndex.busyR.toInt());
      final bg = await dev.getConfig(ConfigIndex.busyG.toInt());
      final bb = await dev.getConfig(ConfigIndex.busyB.toInt());

      // Attempt reading product id via getInfo
      int? pid;
      try {
        final info = await dev.callRpc('device.getInfo', {'unit': dev.instance.unit});
        if (info is Map && info['pid'] != null) {
          pid = (info['pid'] as num).toInt();
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _firmwareTimestamp = timestamp;
        _chipId = chipId;
        _productId = pid;
        _config0 = config0;
        _idleColor = Color.fromARGB(255, r, g, b);
        _busyColor = Color.fromARGB(255, br, bg, bb);
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

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null || timestamp == 0) return 'Unknown';
    try {
      final dt = timestamp > 10000000000
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp.toString();
    }
  }

  String _formatChipId(List<int>? chipId) {
    if (chipId == null || chipId.isEmpty) return 'Unknown';
    return chipId.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  void _showColorPicker(
    String title,
    Color initialColor,
    ValueChanged<Color> onColorConfirmed,
  ) {
    var pickerColor = initialColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
            enableAlpha: false,
            hexInputBar: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              onColorConfirmed(pickerColor);
              Navigator.pop(context);
            },
            child: Text(context.l10n.confirmColorChoice),
          ),
        ],
      ),
    );
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
                Icon(Icons.sensors, color: context.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.remoteReader,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                  onPressed: _isLoading ? null : _fetchHardwareInfo,
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
              _buildReaderContent(context),
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
          Icon(Icons.error_outline, color: context.colorScheme.error),
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
            onPressed: _fetchHardwareInfo,
            child: Text(context.l10n.reconnect),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderContent(BuildContext context) {
    final l10n = context.l10n;
    final pidStr = _productId != null
        ? '0x${_productId!.toRadixString(16).padLeft(4, '0').toUpperCase()}'
        : '0x0147 (HINATA Std)';
    final chipIdStr = _formatChipId(_chipId);
    final dateStr = _formatTimestamp(_firmwareTimestamp);

    final isRainbow = _config0.enableLedRainbow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hardware summary card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.hardwareInfo,
                style: context.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.pidLabel(pidStr), style: context.textTheme.bodySmall),
                  Text(l10n.firmwareDateLabel(dateStr), style: context.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.chipIdLabel(chipIdStr),
                style: context.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Rainbow Switch
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.ledRainbow),
          value: isRainbow,
          onChanged: (val) async {
            final dev = widget.remoteDevice;
            if (dev == null) return;
            setState(() => _config0.enableLedRainbow = val);
            await dev.setConfig(ConfigIndex.config0.toInt(), _config0.asByte());
            if (!val) {
              await dev.resetLed();
            }
          },
        ),

        // Idle Color Tile
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.idleRGB),
          enabled: !isRainbow,
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isRainbow ? Colors.grey : _idleColor,
              shape: BoxShape.circle,
              border: Border.all(color: context.colorScheme.outlineVariant),
            ),
          ),
          onTap: isRainbow
              ? null
              : () {
                  _showColorPicker(l10n.pickFavoriteColor, _idleColor, (color) async {
                    final dev = widget.remoteDevice;
                    if (dev == null) return;
                    setState(() => _idleColor = color);
                    await dev.setLed(color);
                    await dev.setConfig(ConfigIndex.idleR.toInt(), (color.r * 255).round());
                    await dev.setConfig(ConfigIndex.idleG.toInt(), (color.g * 255).round());
                    await dev.setConfig(ConfigIndex.idleB.toInt(), (color.b * 255).round());
                  });
                },
        ),

        // Busy Color Tile
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.busyRGB),
          enabled: !isRainbow,
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isRainbow ? Colors.grey : _busyColor,
              shape: BoxShape.circle,
              border: Border.all(color: context.colorScheme.outlineVariant),
            ),
          ),
          onTap: isRainbow
              ? null
              : () {
                  _showColorPicker(l10n.pickFavoriteColor, _busyColor, (color) async {
                    final dev = widget.remoteDevice;
                    if (dev == null) return;
                    setState(() => _busyColor = color);
                    await dev.setConfig(ConfigIndex.busyR.toInt(), (color.r * 255).round());
                    await dev.setConfig(ConfigIndex.busyG.toInt(), (color.g * 255).round());
                    await dev.setConfig(ConfigIndex.busyB.toInt(), (color.b * 255).round());
                  });
                },
        ),
        const Divider(height: 16),

        // FastRead Switch
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.fastRead),
          value: _config0.segaFastRead,
          onChanged: (val) async {
            final dev = widget.remoteDevice;
            if (dev == null) return;
            setState(() => _config0.segaFastRead = val);
            await dev.setConfig(ConfigIndex.config0.toInt(), _config0.asByte());
          },
        ),
        const SizedBox(height: 12),

        // Firmware Update Button
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: widget.remoteDevice == null
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (context) => RemoteFirmwareDialog(
                        remoteDevice: widget.remoteDevice!,
                      ),
                    );
                  },
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: Text(l10n.firmwareUpdate),
          ),
        ),
      ],
    );
  }
}
