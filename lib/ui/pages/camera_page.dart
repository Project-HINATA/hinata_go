import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/card/aime.dart';
import '../../models/card/scanned_card.dart';
import '../../providers/nfc_provider.dart';
import '../../utils/qr_handler.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  late MobileScannerController controller;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      autoStart: false,
    );
    _startScanner();
  }

  Future<void> _startScanner() async {
    try {
      await controller.start();
    } catch (e) {
      debugPrint('Scanner Error: $e');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && QrHandler.isValidQrData(rawValue)) {
        final accessCodeBytes = Uint8List.fromList(
          rawValue.codeUnits.length >= 20
              ? _hexToBytes(rawValue)
              : rawValue.codeUnits,
        );
        final aime = Aime(Uint8List(4), 0x08, 0x0004, accessCodeBytes);

        ref
            .read(nfcProvider.notifier)
            .handleExternalScan(ScannedCard(card: aime, source: 'QR'));

        if (mounted) {
          Navigator.of(context).pop();
        }
        break;
      }
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    final length = cleanHex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildScanner(),
          const Positioned.fill(child: _ScannerManualOverlay()),
          _buildCloseButton(),
          _buildCameraSwitch(),
          _buildTorchButton(),
          _buildInstruction(),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Positioned.fill(
      child: MobileScanner(
        controller: controller,
        onDetect: _onDetect,
        fit: BoxFit.cover,
        placeholderBuilder: (context) =>
            const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      child: IconButton.filledTonal(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: 24,
        ),
      ),
    );
  }

  Widget _buildCameraSwitch() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 48,
      left: 40,
      child: ValueListenableBuilder<MobileScannerState>(
        valueListenable: controller,
        builder: (context, state, child) {
          final isFront = state.cameraDirection == CameraFacing.front;
          return IconButton.filledTonal(
            isSelected: isFront,
            onPressed: () => controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
            style: IconButton.styleFrom(
              minimumSize: const Size(64, 64),
              iconSize: 28,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTorchButton() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 48,
      right: 40,
      child: ValueListenableBuilder<MobileScannerState>(
        valueListenable: controller,
        builder: (context, state, child) {
          final isTorchOn = state.torchState == TorchState.on;
          return IconButton.filledTonal(
            isSelected: isTorchOn,
            onPressed: () => controller.toggleTorch(),
            icon: const Icon(Icons.flash_off),
            selectedIcon: const Icon(Icons.flash_on),
            style: IconButton.styleFrom(
              minimumSize: const Size(64, 64),
              iconSize: 28,
            ),
          );
        },
      ),
    );
  }

  Widget _buildInstruction() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 400,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          'Scan QR Code',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ScannerManualOverlay extends StatelessWidget {
  const _ScannerManualOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _ScannerPainter(
        scrimColor: colorScheme.scrim.withValues(alpha: 0.45),
        borderColor: colorScheme.secondaryContainer,
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  final Color scrimColor;
  final Color borderColor;

  _ScannerPainter({required this.scrimColor, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final screenWidth = size.width;
    final holeSize = screenWidth * 0.6; // Smaller: 60%
    final holeRadius = 28.0;

    final holeRect = Rect.fromCenter(
      center: Offset(
        size.width / 2,
        (size.height / 2) - 140,
      ), // Shifted further UP
      width: holeSize,
      height: holeSize,
    );

    // 1. Draw Scrim with Hole (PathFillType.evenOdd prevents corner glitches)
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(holeRect, Radius.circular(holeRadius)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = scrimColor);

    // 2. Draw Border around the hole
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(holeRect, Radius.circular(holeRadius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
