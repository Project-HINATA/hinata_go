import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:hinata_go/services/nfc_service.dart';
import 'package:uuid/uuid.dart';

import '../../models/scan_log.dart';
import '../../models/bag_card.dart';
import '../../models/parsed_card.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_service.dart';
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
  late GoRouter _router;
  bool _isNfcScanning = false;
  String _nfcStatus = 'Ready to scan NFC tags';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      autoStart: false,
    );
    WidgetsBinding.instance.addObserver(this);
    _startNfc();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router = GoRouter.of(context);
    _router.routerDelegate.addListener(_routeListener);
  }

  void _routeListener() {
    final location =
        _router.routerDelegate.currentConfiguration.last.matchedLocation;
    final enableCamera = ref.read(settingsProvider).enableCamera;

    if (location == '/reader') {
      _startNfc();
      if (enableCamera) _safeStartCamera();
    } else { 
      _stopNfc();
      _safeStopCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final location =
          _router.routerDelegate.currentConfiguration.last.matchedLocation;
      final enableCamera = ref.read(settingsProvider).enableCamera;

      if (location == '/reader') {
        _startNfc();
        if (enableCamera) _safeStartCamera();
      }
    } else if (state == AppLifecycleState.paused) {
      _stopNfc();
      _safeStopCamera();
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_routeListener);
    WidgetsBinding.instance.removeObserver(this);
    _stopNfc();
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

  Future<void> _startNfc() async {
    if (_isNfcScanning) return;
    try {
      NfcAvailability availability = await NfcManager.instance
          .checkAvailability();
      if (availability != NfcAvailability.enabled) {
        if (mounted) {
          setState(() {
            _nfcStatus = 'NFC is not available or disabled.';
          });
        }
        return;
      }

      setState(() {
        _isNfcScanning = true;
        _nfcStatus = 'Listening for NFC...';
      });

      await NfcManager.instance.startSession(
        noPlatformSoundsAndroid: true,
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso18092},
        onDiscovered: _onNfcDiscovered,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isNfcScanning = false;
          _nfcStatus = 'NFC Error: $e';
        });
      }
    }
  }

  void _stopNfc() {
    if (_isNfcScanning) {
      try {
        NfcManager.instance.stopSession();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isNfcScanning = false;
        });
      }
    }
  }

  Future<void> _onNfcDiscovered(NfcTag tag) async {
    final parsedCard = await handleNfcTag(tag);
    if (parsedCard != null) {
      if (parsedCard.apiType != 'Unknown' && parsedCard.value.isNotEmpty) {
        _handleReadData(parsedCard);
      }
    }
  }

  void _onQrDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && QrHandler.isValidQrData(rawValue)) {
        _handleReadData(
          ParsedCard(
            value: rawValue,
            showValue: rawValue,
            source: 'QR',
            apiType: 'aime',
            displayType: 'QR Code',
          ),
        );
        break;
      }
    }
  }

  void _onResendHistoryItem(ScanLog log) {
    if (_isProcessing) return;
    _handleReadData(
      ParsedCard(
        value: log.value,
        showValue: log.showValue,
        source: log.source,
        apiType: log.apiType,
        displayType: log.displayType,
      ),
    );
  }

  Future<void> _handleReadData(ParsedCard card) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final enableSecondaryConfirmation = ref
        .read(settingsProvider)
        .enableSecondaryConfirmation;

    if (enableSecondaryConfirmation) {
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => _ConfirmSendDialog(card: card),
      );
      if (!mounted) return;
      if (shouldSend != true) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }
    }

    final activeInstance = ref.read(activeInstanceProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Save to history automatically as a ScanLog
    final newLog = ScanLog(
      id: const Uuid().v4(),
      value: card.value,
      showValue: card.showValue,
      source: card.source,
      apiType: card.apiType,
      displayType: card.displayType,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    // Also auto-save to the 'History' folder in the Saved Cards
    final newCard = BagCard(
      id: const Uuid().v4(),
      name: card.displayType,
      value: card.value,
      showValue: card.showValue,
      folderId: 'history_folder',
      source: card.source,
      apiType: card.apiType,
      displayType: card.displayType,
    );
    ref.read(bagCardsProvider.notifier).addCard(newCard);

    if (activeInstance == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Card read, but no active instance set to send data.'),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Sending data to ${activeInstance.name}...')),
      );

      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.sendCardData(
        instance: activeInstance,
        type: card.apiType,
        value: card.value,
      );

      if (!mounted) return;

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Success: Data sent.')),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed: Could not send data.')),
        );
      }
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Removed _showInstanceSelectionDialog as it is now handled by InstancesPage

  // ---------------------------------------------------------------------------
  // Builder methods — extracted from build() to flatten nesting
  // ---------------------------------------------------------------------------

  /// Animated pill showing NFC scanning status.
  Widget _buildNfcStatusPill() {
    final colorScheme = Theme.of(context).colorScheme;
    final Color bgColor = _isNfcScanning
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final Color fgColor = _isNfcScanning
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.nfc,
              color: _isNfcScanning
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _nfcStatus,
                key: ValueKey(_nfcStatus),
                style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// QR camera preview with overlay and processing indicator.
  Widget _buildQrScanner() {
    final colorScheme = Theme.of(context).colorScheme;

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
              if (state.isInitialized &&
                  !state.isRunning &&
                  state.error == null) {
                return _buildCameraPlaceholder(colorScheme);
              }
              if (!state.isInitialized && state.error == null) {
                return _buildCameraPlaceholder(colorScheme);
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
          if (_isProcessing)
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

  /// Placeholder shown while the camera is loading, paused, or errored.
  Widget _buildCameraPlaceholder(
    ColorScheme colorScheme, {
    MobileScannerException? error,
  }) {
    if (error == null) {
      return const SizedBox.shrink();
    }

    final color = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    String message = 'Camera Error';
    IconData icon = Icons.error_outline;

    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
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

  /// Scan-target crosshair overlay.
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

  /// Card showing the active instance or a "no instance" warning.
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

  /// Row content when an instance is selected.
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

  /// Row content when no instance is selected.
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

  /// History header + recent scans list.
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

  /// A single history list item.
  Widget _buildHistoryItem(ScanLog log) {
    final colorScheme = Theme.of(context).colorScheme;

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
        onPressed: _isProcessing ? null : () => _onResendHistoryItem(log),
        tooltip: 'Resend to active instance',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final activeInstance = ref.watch(activeInstanceProvider);
    final scanLogs = ref.watch(scanLogsProvider).reversed.take(5).toList();

    // We must rebuild when the setting changes to stop/start camera dynamically
    final enableCamera = ref.watch(settingsProvider).enableCamera;

    // Stop or start the camera based on settings immediately upon build if on Reader page
    // Since we are in build, we use post-frame callback or let route listener handle it,
    // but just checking the flag is enough to hide it. To actually stop the hardware:
    if (!enableCamera && _cameraController.value.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeStopCamera();
      });
    } else if (enableCamera &&
        !_cameraController.value.isRunning &&
        ModalRoute.of(context)?.isCurrent == true) {
      // Start only if currently visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeStartCamera();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC & QR Reader'),
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

class _ConfirmSendDialog extends StatelessWidget {
  final ParsedCard card;
  const _ConfirmSendDialog({required this.card});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Send'),
      content: Text(
        'Are you sure you want to send this ${card.displayType} card?\nValue: ${card.value}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
