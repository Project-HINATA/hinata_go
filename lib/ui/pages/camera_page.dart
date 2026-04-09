import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/card/aime.dart';
import '../../models/card/scanned_card.dart';
import '../../providers/nfc_provider.dart';
import '../../utils/qr_handler.dart';

class CameraPage extends HookConsumerWidget {
  const CameraPage({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMemoized(
      () => MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        autoStart: false,
      ),
    );

    final isNavigatingRef = useRef(false);

    useEffect(() {
      controller.start().catchError((e) {
        debugPrint('Scanner Error: $e');
      });
      return () => controller.dispose();
    }, [controller]);

    void onDetect(BarcodeCapture capture) {
      if (isNavigatingRef.value) return;

      for (final barcode in capture.barcodes) {
        final rawValue = barcode.rawValue;
        if (rawValue != null && QrHandler.isValidQrData(rawValue)) {
          isNavigatingRef.value = true; // Set flag immediately

          final accessCodeBytes = Uint8List.fromList(
            rawValue.codeUnits.length >= 20
                ? _hexToBytes(rawValue)
                : rawValue.codeUnits,
          );
          final aime = Aime(Uint8List(4), 0x08, 0x0004, accessCodeBytes);

          ref
              .read(nfcProvider.notifier)
              .handleExternalScan(ScannedCard(card: aime, source: 'QR'));

          // Stop scanner before popping to prevent further detections
          controller.stop();
          context.navigator.pop();
          break;
        }
      }
    }

    useListenable(
      controller,
    ); // Rebuild when controller state changes (torch, camera facing)

    return Scaffold(
      backgroundColor: Colors.black,
      body: _CameraPageBody(
        controller: controller,
        onDetect: onDetect,
        closeButton: _buildCloseButton(context),
        cameraSwitchButton: _buildCameraSwitch(context, controller),
        torchButton: _buildTorchButton(context, controller),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Positioned(
      top: context.mediaQuery.padding.top + 16,
      left: 24,
      child: IconButton.filledTonal(
        onPressed: () => context.navigator.pop(),
        icon: const Icon(Icons.close),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: 24,
        ),
      ),
    );
  }

  Widget _buildCameraSwitch(
    BuildContext context,
    MobileScannerController controller,
  ) {
    final state = controller.value;
    final isFront = state.cameraDirection == CameraFacing.front;
    return Positioned(
      bottom: context.mediaQuery.padding.bottom + 48,
      left: 40,
      child: IconButton.filledTonal(
        isSelected: isFront,
        onPressed: () => controller.switchCamera(),
        icon: const Icon(Icons.cameraswitch),
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          iconSize: 28,
        ),
      ),
    );
  }

  Widget _buildTorchButton(
    BuildContext context,
    MobileScannerController controller,
  ) {
    final state = controller.value;
    final isTorchOn = state.torchState == TorchState.on;
    return Positioned(
      bottom: context.mediaQuery.padding.bottom + 48,
      right: 40,
      child: IconButton.filledTonal(
        isSelected: isTorchOn,
        onPressed: () => controller.toggleTorch(),
        icon: const Icon(Icons.flash_off),
        selectedIcon: const Icon(Icons.flash_on),
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          iconSize: 28,
        ),
      ),
    );
  }
}

class _CameraPageBody extends StatelessWidget {
  const _CameraPageBody({
    required this.controller,
    required this.onDetect,
    required this.closeButton,
    required this.cameraSwitchButton,
    required this.torchButton,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final Widget closeButton;
  final Widget cameraSwitchButton;
  final Widget torchButton;

  @override
  Widget build(BuildContext context) {
    final overlayLayout = _ScannerOverlayLayout.fromContext(context);

    return Stack(
      children: [
        _ScannerViewport(controller: controller, onDetect: onDetect),
        Positioned.fill(
          child: _ScannerManualOverlay(holeRect: overlayLayout.holeRect),
        ),
        closeButton,
        cameraSwitchButton,
        torchButton,
        _ScannerInstruction(holeRect: overlayLayout.holeRect),
      ],
    );
  }
}

class _ScannerViewport extends StatelessWidget {
  const _ScannerViewport({required this.controller, required this.onDetect});

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: MobileScanner(
        controller: controller,
        onDetect: onDetect,
        fit: BoxFit.cover,
        placeholderBuilder: (context) =>
            const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ScannerOverlayLayout {
  const _ScannerOverlayLayout({required this.holeRect});

  factory _ScannerOverlayLayout.fromContext(BuildContext context) {
    final size = context.mediaQuery.size;
    final holeSize = size.width * 0.6;

    return _ScannerOverlayLayout(
      holeRect: Rect.fromCenter(
        center: Offset(size.width / 2, (size.height / 2) - 140),
        width: holeSize,
        height: holeSize,
      ),
    );
  }

  final Rect holeRect;
}

class _ScannerInstruction extends StatelessWidget {
  const _ScannerInstruction({required this.holeRect});

  final Rect holeRect;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: holeRect.bottom + 40,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          context.l10n.cameraScanInstruction,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ScannerManualOverlay extends StatelessWidget {
  final Rect holeRect;
  const _ScannerManualOverlay({required this.holeRect});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _ScannerPainter(
        scrimColor: colorScheme.scrim.withValues(alpha: 0.45),
        borderColor: colorScheme.secondaryContainer,
        holeRect: holeRect,
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  final Color scrimColor;
  final Color borderColor;
  final Rect holeRect;

  _ScannerPainter({
    required this.scrimColor,
    required this.borderColor,
    required this.holeRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const holeRadius = 28.0;

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
  bool shouldRepaint(covariant _ScannerPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.borderColor != borderColor;
  }
}
