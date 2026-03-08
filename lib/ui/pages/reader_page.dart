import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata_go/services/nfc_handler.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/scan_log.dart';
import '../../models/card/scanned_card.dart';
import '../../models/card/aime.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/icon_utils.dart';
import '../../utils/qr_handler.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  late MobileScannerController _cameraController;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      autoStart: false,
    );
    WidgetsBinding.instance.addObserver(this);

    // Auto-start NFC session if it's not already scanning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nfcHandlerProvider.notifier).startSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final enableCamera = ref.read(settingsProvider).enableCamera;
      if (enableCamera) _safeStartCamera();
    } else if (state == AppLifecycleState.paused) {
      _safeStopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeStopCamera();
    Future.delayed(const Duration(milliseconds: 200), () {
      _cameraController.dispose();
    });
    super.dispose();
  }

  void _safeStartCamera() {
    try {
      if (_cameraController.value.isStarting ||
          _cameraController.value.isRunning ||
          _cameraController.value.error != null) {
        return;
      }
      _cameraController.start();
    } catch (e) {
      debugPrint('Error starting camera: $e');
    }
  }

  void _safeStopCamera() {
    try {
      if (_cameraController.value.isRunning) {
        _cameraController.stop();
      }
    } catch (e) {
      debugPrint('Error stopping camera: $e');
    }
  }

  void _onQrDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && QrHandler.isValidQrData(rawValue)) {
        // QR codes are treated as Aime type
        final accessCodeBytes = Uint8List.fromList(
          rawValue.codeUnits.length >= 20
              ? _hexToBytes(rawValue)
              : rawValue.codeUnits,
        );
        final aime = Aime(
          Uint8List(4), // placeholder id
          0x08, // placeholder sak
          0x0004, // placeholder atqa
          accessCodeBytes,
        );
        ref
            .read(nfcHandlerProvider.notifier)
            .handleExternalScan(ScannedCard(card: aime, source: 'QR'));
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

  void _onResendHistoryItem(ScanLog log) {
    ref
        .read(nfcHandlerProvider.notifier)
        .handleExternalScan(ScannedCard(card: log.card, source: log.source));
  }

  Widget _buildNfcStatusPill() {
    final nfcState = ref.watch(nfcHandlerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final Color bgColor = nfcState.isScanning
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final Color fgColor = nfcState.isScanning
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: InkWell(
          onTap: () {
            if (nfcState.isScanning) {
              ref.read(nfcHandlerProvider.notifier).stopSession();
            } else {
              ref.read(nfcHandlerProvider.notifier).startSession();
            }
          },
          borderRadius: BorderRadius.circular(30),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.nfc,
                color: nfcState.isScanning
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  nfcState.status,
                  key: ValueKey(nfcState.status),
                  style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrScanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final nfcState = ref.watch(nfcHandlerProvider);

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _cameraController,
            builder: (context, state, _) {
              if (!state.isInitialized || !state.isRunning) {
                return _buildCameraPlaceholder(colorScheme, error: state.error);
              }
              return const SizedBox.shrink();
            },
          ),
          MobileScanner(
            controller: _cameraController,
            errorBuilder: (context, error) {
              return _buildCameraPlaceholder(colorScheme, error: error);
            },
            onDetect: _onQrDetect,
          ),
          if (nfcState.isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _cameraController,
            builder: (context, state, _) {
              if (!state.isRunning) return const SizedBox.shrink();
              return _buildScanTargetOverlay();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPlaceholder(
    ColorScheme colorScheme, {
    MobileScannerException? error,
  }) {
    final color = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    String message = error == null ? 'Camera Paused' : 'Camera Error';
    IconData icon = error == null ? Icons.videocam_off : Icons.error_outline;

    if (error?.errorCode == MobileScannerErrorCode.permissionDenied) {
      message = 'Camera Permission Denied';
      icon = Icons.no_photography;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: color),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildScanTargetOverlay() {
    return Center(
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildInstanceCard(dynamic activeInstance) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/instances'),
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: activeInstance != null
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: activeInstance != null
              ? _buildActiveInstanceRow(activeInstance)
              : _buildNoInstanceRow(),
        ),
      ),
    );
  }

  Widget _buildActiveInstanceRow(dynamic activeInstance) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgColor = colorScheme.onPrimaryContainer;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: fgColor.withValues(alpha: 0.1),
          child: Text(
            IconUtils.getEmoji(activeInstance.icon),
            style: const TextStyle(fontSize: 24),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activeInstance.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activeInstance.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fgColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.arrow_drop_down, color: fgColor),
      ],
    );
  }

  Widget _buildNoInstanceRow() {
    final fgColor = Theme.of(context).colorScheme.onErrorContainer;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: fgColor.withValues(alpha: 0.1),
          child: Icon(Icons.warning, color: fgColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'No active instance selected.\nTap to select.',
            style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
          ),
        ),
        Icon(Icons.arrow_drop_down, color: fgColor),
      ],
    );
  }

  Widget _buildHistorySection(List<ScanLog> scanLogs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Scans', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => context.push('/scan_logs'),
              child: const Text('View All Logs'),
            ),
          ],
        ),
        const Divider(),
        if (scanLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('No recent scans.')),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: scanLogs.length,
            itemBuilder: (context, index) => _buildHistoryItem(scanLogs[index]),
          ),
      ],
    );
  }

  Widget _buildHistoryItem(ScanLog log) {
    final colorScheme = Theme.of(context).colorScheme;
    final nfcState = ref.watch(nfcHandlerProvider);

    String displaySource = log.source;
    if (log.source == 'NFC') {
      if (log.apiType != 'nfc') {
        displaySource = 'NFC (${log.displayType})';
      }
    } else if (log.source == 'Direct') {
      displaySource = 'Saved Cards';
    }

    IconData sourceIcon = Icons.qr_code;
    if (log.source == 'NFC') sourceIcon = Icons.nfc;
    if (log.source == 'Direct') sourceIcon = Icons.credit_card;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(
          sourceIcon,
          color: colorScheme.onSecondaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        log.showValue,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '$displaySource • ${log.timestamp.toString().substring(5, 16)}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.send, size: 20),
        onPressed: nfcState.isProcessing
            ? null
            : () => _onResendHistoryItem(log),
        tooltip: 'Resend to active instance',
      ),
      onTap: () => context.push('/card_detail', extra: log.card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeInstance = ref.watch(activeInstanceProvider);
    final scanLogs = ref.watch(scanLogsProvider).reversed.take(5).toList();
    final enableCamera = ref.watch(settingsProvider).enableCamera;

    if (!enableCamera && _cameraController.value.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeStopCamera();
      });
    } else if (enableCamera &&
        !_cameraController.value.isRunning &&
        ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeStartCamera();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/logo.svg',
              height: 24,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurface,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
            const Text('HINATA Go'),
          ],
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _cameraController,
            builder: (context, state, child) {
              if (!state.isInitialized || !state.isRunning || !enableCamera) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.cameraswitch),
                onPressed: () => _cameraController.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNfcStatusPill(),
              if (enableCamera) ...[
                const SizedBox(height: 16),
                _buildQrScanner(),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Point camera at QR Code',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildInstanceCard(activeInstance),
              const SizedBox(height: 32),
              _buildHistorySection(scanLogs),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
