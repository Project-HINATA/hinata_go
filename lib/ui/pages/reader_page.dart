import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:uuid/uuid.dart';

import '../../models/saved_card.dart';
import '../../providers/app_state_provider.dart';
import '../../services/api_service.dart';

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
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
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
    if (location == '/reader') {
      _startNfc();
      _cameraController.start();
    } else {
      _stopNfc();
      _cameraController.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final location =
          _router.routerDelegate.currentConfiguration.last.matchedLocation;
      if (location == '/reader') {
        _startNfc();
        _cameraController.start();
      }
    } else if (state == AppLifecycleState.paused) {
      _stopNfc();
      _cameraController.stop();
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_routeListener);
    WidgetsBinding.instance.removeObserver(this);
    _stopNfc();
    _cameraController.dispose();
    super.dispose();
  }

  String _toHexString(Uint8List bytes) {
    return bytes
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
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
        _nfcStatus = 'Listening for NFC (NfcA/NfcF)...';
      });

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso18092},
        onDiscovered: (NfcTag tag) async {
          final nfcA = NfcAAndroid.from(tag);
          final nfcF = NfcFAndroid.from(tag);

          String type = '';
          String uid = '';

          if (nfcA != null) {
            type = 'NfcA';
            uid = _toHexString(nfcA.tag.id);
          } else if (nfcF != null) {
            type = 'NfcF';
            uid = _toHexString(nfcF.tag.id);
          } else {
            type = 'Unknown';
            uid = _toHexString(NfcAAndroid.from(tag)?.tag.id ?? Uint8List(0));
          }

          if (type != 'Unknown' && uid.isNotEmpty) {
            _handleReadData(type, uid);
          }
        },
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

  Future<void> _handleReadData(String type, String value) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    final activeInstance = ref.read(activeInstanceProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Save to history automatically
    final newCard = SavedCard(
      id: const Uuid().v4(),
      name: '$type Scanned Card',
      type: type,
      value: value,
    );
    ref.read(savedCardsProvider.notifier).addCard(newCard);

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
        type: type,
        value: value,
      );

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

  IconData _getIconData(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'cloud':
        return Icons.cloud;
      case 'computer':
        return Icons.computer;
      case 'api':
        return Icons.api;
      case 'webhook':
        return Icons.webhook;
      default:
        return Icons.dns;
    }
  }

  void _showInstanceSelectionDialog() {
    final instances = ref.read(instancesProvider);
    final activeId = ref.read(activeInstanceIdProvider);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Active Instance'),
          content: SizedBox(
            width: double.maxFinite,
            child: instances.isEmpty
                ? const Text(
                    'No instances configured. Add them in the Instances tab.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: instances.length,
                    itemBuilder: (context, index) {
                      final instance = instances[index];
                      final isActive = instance.id == activeId;
                      return ListTile(
                        leading: Icon(_getIconData(instance.icon)),
                        title: Text(instance.name),
                        subtitle: Text(
                          instance.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isActive
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : null,
                        onTap: () {
                          ref
                              .read(activeInstanceIdProvider.notifier)
                              .setActiveId(instance.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(activeInstanceIdProvider.notifier).setActiveId(null);
                Navigator.pop(context);
              },
              child: const Text('Clear Active'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

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
          _buildCameraPlaceholder(colorScheme),
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  _handleReadData('QR', barcode.rawValue!);
                  break;
                }
              }
            },
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

  /// Placeholder shown while the camera is loading or paused.
  Widget _buildCameraPlaceholder(ColorScheme colorScheme) {
    final color = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner, size: 64, color: color),
          const SizedBox(height: 8),
          Text('Camera Loading/Paused', style: TextStyle(color: color)),
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
      onTap: _showInstanceSelectionDialog,
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
          child: Icon(_getIconData(activeInstance.icon), color: fgColor),
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
  Widget _buildHistorySection(List<SavedCard> savedCards) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('History', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => context.go('/history'),
              child: const Text('View All'),
            ),
          ],
        ),
        const Divider(),
        if (savedCards.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('No recent scans.')),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: savedCards.length,
            itemBuilder: (context, index) =>
                _buildHistoryItem(savedCards[index]),
          ),
      ],
    );
  }

  /// A single history list item.
  Widget _buildHistoryItem(SavedCard card) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(
          card.type.contains('Nfc') ? Icons.nfc : Icons.qr_code,
          color: colorScheme.onSecondaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        card.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('${card.type} • ${card.value}'),
      trailing: IconButton(
        icon: const Icon(Icons.send, size: 20),
        onPressed: _isProcessing
            ? null
            : () => _handleReadData(card.type, card.value),
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
    final savedCards = ref.watch(savedCardsProvider).reversed.take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('NFC & QR Reader')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNfcStatusPill(),
              const SizedBox(height: 16),
              _buildQrScanner(),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Point camera at QR Code',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              _buildInstanceCard(activeInstance),
              const SizedBox(height: 32),
              _buildHistorySection(savedCards),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
