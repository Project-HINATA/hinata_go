import 'package:flutter/material.dart';
import 'package:hinata_go/services/communication/usb_hinata_impl.dart';
import 'package:hinata_go/models/hardware_config.dart';
import 'package:hinata_go/utils/gamma.dart';

class BrightnessSlider extends StatefulWidget {
  final UsbHinataDeviceImpl device;
  const BrightnessSlider({required this.device, super.key});

  @override
  State<BrightnessSlider> createState() => _BrightnessSliderState();
}

class _BrightnessSliderState extends State<BrightnessSlider> {
  late int _currentBrightness;

  @override
  void initState() {
    super.initState();
    _currentBrightness = widget.device.segaBrightness;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            Slider(
              value: mapWithGamma(_currentBrightness, 0.5),
              onChanged: (value) {
                final brightnessValue = unmapWithGamma(value, 0.5);
                setState(() {
                  _currentBrightness = brightnessValue;
                });
                widget.device
                    .setLed(
                      Color.fromARGB(
                        255,
                        brightnessValue,
                        brightnessValue,
                        brightnessValue,
                      ),
                    )
                    .ignore();
              },
              onChangeEnd: (value) async {
                final brightnessValue = unmapWithGamma(value, 0.5);
                await widget.device.setConfig(
                  ConfigIndex.segaBrightness.toInt(),
                  brightnessValue,
                );
                await widget.device.resetLed();
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Dim'), Text('Bright')],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
