import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:hinata_go/models/hardware_config.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';

class GlobalSettingsCard extends StatefulWidget {
  final UsbHinataDeviceImpl device;
  const GlobalSettingsCard({required this.device, super.key});

  @override
  State<GlobalSettingsCard> createState() => _GlobalSettingsCardState();
}

class _GlobalSettingsCardState extends State<GlobalSettingsCard> {
  Color _pickerColor = Colors.blue;

  void _showColorPicker(
    String title,
    Color initialColor,
    Function(Color) onColorChanged,
  ) {
    _pickerColor = initialColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _pickerColor,
            onColorChanged: (color) => _pickerColor = color,
            enableAlpha: false,
            hexInputBar: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.navigator.pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              onColorChanged(_pickerColor);
              context.navigator.pop();
            },
            child: Text(context.l10n.confirmColorChoice),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hinata = widget.device;
    final config0 = hinata.config0;
    final isHinata = hinata.productName == "HINATA";
    final isRainbow = config0.enableLedRainbow;
    final l10n = context.l10n;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (isHinata) ...[
            _ConfigSwitchTile(
              title: l10n.ledRainbow,
              value: isRainbow,
              onChanged: (value) async {
                config0.enableLedRainbow = value;
                await hinata.setConfig(
                  ConfigIndex.config0.toInt(),
                  config0.asByte(),
                );
                if (!value) {
                  await hinata.resetLed();
                }
                setState(() {});
              },
            ),
            const _SettingsDivider(),
            _ColorSettingTile(
              title: l10n.idleRGB,
              enabled: !isRainbow,
              color: hinata.idleRGB,
              onTap: () {
                _showColorPicker(l10n.pickFavoriteColor, hinata.idleRGB, (
                  color,
                ) async {
                  await hinata.setLed(color);
                  await hinata.setConfig(
                    ConfigIndex.idleR.toInt(),
                    (color.r * 255).round(),
                  );
                  await hinata.setConfig(
                    ConfigIndex.idleG.toInt(),
                    (color.g * 255).round(),
                  );
                  await hinata.setConfig(
                    ConfigIndex.idleB.toInt(),
                    (color.b * 255).round(),
                  );
                  hinata.idleRGB = color;
                  setState(() {});
                });
              },
            ),
            const _SettingsDivider(),
            _ColorSettingTile(
              title: l10n.busyRGB,
              enabled: !isRainbow,
              color: hinata.busyRGB,
              onTap: () {
                _showColorPicker(l10n.pickFavoriteColor, hinata.busyRGB, (
                  color,
                ) async {
                  await hinata.setConfig(
                    ConfigIndex.busyR.toInt(),
                    (color.r * 255).round(),
                  );
                  await hinata.setConfig(
                    ConfigIndex.busyG.toInt(),
                    (color.g * 255).round(),
                  );
                  await hinata.setConfig(
                    ConfigIndex.busyB.toInt(),
                    (color.b * 255).round(),
                  );
                  hinata.busyRGB = color;
                  setState(() {});
                });
              },
            ),
            const _SettingsDivider(),
          ],
          _ConfigSwitchTile(
            title: l10n.uniqueDescriptor,
            value: config0.serialDescriptorUnique,
            onChanged: (value) async {
              config0.serialDescriptorUnique = value;
              await hinata.setConfig(
                ConfigIndex.config0.toInt(),
                config0.asByte(),
              );
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class SegaSettingsCard extends StatefulWidget {
  final UsbHinataDeviceImpl device;
  const SegaSettingsCard({required this.device, super.key});

  @override
  State<SegaSettingsCard> createState() => _SegaSettingsCardState();
}

class _SegaSettingsCardState extends State<SegaSettingsCard> {
  // Simple gamma mapping to match hinatacc
  double mapWithGamma(int value, double gamma) {
    return math.pow(value / 255.0, gamma).toDouble();
  }

  int unmapWithGamma(double value, double gamma) {
    return (math.pow(value, 1.0 / gamma) * 255.0).round();
  }

  @override
  Widget build(BuildContext context) {
    final hinata = widget.device;
    final config0 = hinata.config0;
    final isHinata = hinata.productName == "HINATA";
    final l10n = context.l10n;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (isHinata) ...[
            _BrightnessSetting(
              title: l10n.segaBrightness,
              value: mapWithGamma(hinata.segaBrightness, 0.5),
              onChanged: (value) {
                setState(() {
                  hinata.segaBrightness = unmapWithGamma(value, 0.5);
                  hinata
                      .setLed(
                        Color.fromARGB(
                          255,
                          hinata.segaBrightness,
                          hinata.segaBrightness,
                          hinata.segaBrightness,
                        ),
                      )
                      .ignore();
                });
              },
              onChangeEnd: (value) async {
                await hinata.setConfig(
                  ConfigIndex.segaBrightness.toInt(),
                  hinata.segaBrightness,
                );
                await hinata.resetLed();
              },
            ),
            const _SettingsDivider(),
          ],
          _DropdownSettingTile<bool>(
            title: l10n.segaFwHw,
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<bool>(
                value: config0.segaHwFw,
                items: [
                  DropdownMenuItem(value: false, child: Text('837-15396')),
                  DropdownMenuItem(value: true, child: Text('TN32MSEC003S')),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    config0.segaHwFw = value;
                    await hinata.setConfig(
                      ConfigIndex.config0.toInt(),
                      config0.asByte(),
                    );
                    setState(() {});
                  }
                },
              ),
            ),
          ),
          const _SettingsDivider(),
          _ConfigSwitchTile(
            title: l10n.segaFastRead,
            value: config0.segaFastRead,
            onChanged: (value) async {
              config0.segaFastRead = value;
              await hinata.setConfig(
                ConfigIndex.config0.toInt(),
                config0.asByte(),
              );
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class CardIOSettingsCard extends StatefulWidget {
  final UsbHinataDeviceImpl device;
  const CardIOSettingsCard({required this.device, super.key});

  @override
  State<CardIOSettingsCard> createState() => _CardIOSettingsCardState();
}

class _CardIOSettingsCardState extends State<CardIOSettingsCard> {
  @override
  Widget build(BuildContext context) {
    final hinata = widget.device;
    final config0 = hinata.config0;
    final l10n = context.l10n;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ConfigSwitchTile(
            title: l10n.cardioDisableIso14443a,
            value: config0.cardioDisableIso14443a,
            onChanged: (value) async {
              config0.cardioDisableIso14443a = value;
              await hinata.setConfig(
                ConfigIndex.config0.toInt(),
                config0.asByte(),
              );
              setState(() {});
            },
          ),
          const _SettingsDivider(),
          _ConfigSwitchTile(
            title: l10n.cardioIso14443aE004,
            value: config0.cardioIso14443aStartWithE004,
            onChanged: config0.cardioDisableIso14443a
                ? null
                : (value) async {
                    config0.cardioIso14443aStartWithE004 = value;
                    await hinata.setConfig(
                      ConfigIndex.config0.toInt(),
                      config0.asByte(),
                    );
                    setState(() {});
                  },
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1);
  }
}

class _ConfigSwitchTile extends StatelessWidget {
  const _ConfigSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ColorSettingTile extends StatelessWidget {
  const _ColorSettingTile({
    required this.title,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final String title;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      enabled: enabled,
      trailing: _ColorPreview(color: color),
      onTap: onTap,
    );
  }
}

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.colorScheme.outlineVariant),
      ),
    );
  }
}

class _BrightnessSetting extends StatelessWidget {
  const _BrightnessSetting({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.bodyLarge),
          Slider(value: value, onChanged: onChanged, onChangeEnd: onChangeEnd),
        ],
      ),
    );
  }
}

class _DropdownSettingTile<T> extends StatelessWidget {
  const _DropdownSettingTile({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(title), trailing: trailing);
  }
}
