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
      if (!_cameraController.value.isInitialized) {
        _cameraController.start();
      }
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
      }
    } else if (state == AppLifecycleState.paused) {
      _stopNfc();
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

  @override
  Widget build(BuildContext context) {
    final activeInstance = ref.watch(activeInstanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Card'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: activeInstance != null
                ? Colors.green.withOpacity(0.2)
                : Colors.orange.withOpacity(0.2),
            child: Text(
              activeInstance != null
                  ? 'Active Instance: ${activeInstance.name}'
                  : 'No active instance selected',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // QR Scanner Background
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleReadData('QR', barcode.rawValue!);
                  break; // handle first valid
                }
              }
            },
          ),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
          // Top section message
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _isProcessing ? 'Processing...' : 'Point camera at QR Code',
                key: ValueKey(_isProcessing),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // NFC Status Bottom Sheet style
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isNfcScanning
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.nfc,
                        color: _isNfcScanning
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade600,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NFC Sensor',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _nfcStatus,
                              key: ValueKey(_nfcStatus),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
