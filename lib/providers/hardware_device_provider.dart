import 'dart:async';
import 'dart:developer';

import 'package:hinata_card_io/hinata_card_io.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import 'current_scan_session_provider.dart';
import 'nfc_provider.dart';
import 'firmware_provider.dart';
import '../models/card/invalid_mifare.dart';
import '../models/card/scanned_card.dart';
import '../services/nfc/card_reader_engine.dart';

class HardwareDeviceState {
  final HinataReader? connectedDevice;
  final bool hidAvailable;
  final bool isConnecting;
  final String? error;
  final String? firmwareVersion;
  final int? productId;
  final bool isUpdating;

  HardwareDeviceState({
    this.connectedDevice,
    this.hidAvailable = false,
    this.isConnecting = false,
    this.error,
    this.firmwareVersion,
    this.productId,
    this.isUpdating = false,
  });

  HardwareDeviceState copyWith({
    HinataReader? connectedDevice,
    bool? hidAvailable,
    bool? isConnecting,
    String? error,
    String? firmwareVersion,
    int? productId,
    bool? isUpdating,
    bool clearDevice = false,
  }) {
    return HardwareDeviceState(
      connectedDevice: clearDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      hidAvailable: hidAvailable ?? this.hidAvailable,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
      firmwareVersion: clearDevice
          ? null
          : (firmwareVersion ?? this.firmwareVersion),
      productId: clearDevice ? null : (productId ?? this.productId),
      isUpdating: isUpdating ?? this.isUpdating,
    );
  }
}

class HardwareDeviceNotifier extends Notifier<HardwareDeviceState> {
  final HinataReaderManager _readerManager = HinataReaderManager();
  int _connectGeneration = 0;
  _PendingReadFailure? _pendingReadFailure;
  _PendingReadFailure? _confirmedReadFailure;

  static const Duration _readFailureConfirmWindow = Duration(seconds: 1);

  @override
  HardwareDeviceState build() {
    final hidAvailable = _readerManager.isAvailable;
    _initHidListeners();
    return HardwareDeviceState(hidAvailable: hidAvailable);
  }

  void _initHidListeners() {
    final canUseHid = _readerManager.isAvailable;
    if (!canUseHid) {
      log('HID unavailable on current platform/browser, skipping HID init.');
      return;
    }

    _readerManager.onConnect((event) {
      log("Auto-connected to device: ${event.device}");
      unawaited(_connectToHidDeviceWhenReady(event.device));
    });

    _readerManager.onDisconnect((event) {
      log("Disconnected from device: ${event.device}");
      _connectGeneration++;

      // Protect state if we are currently flashing/updating
      if (state.isUpdating) {
        log("Ignoring disconnect during update mode.");
        return;
      }

      final reader = state.connectedDevice;
      if (reader != null) {
        if (reader.deviceId == event.device.productId.toString()) {
          unawaited(reader.disconnect());
          ref
              .read(currentScanSessionProvider.notifier)
              .markCardRemoved(source: 'HINATA');
          state = state.copyWith(clearDevice: true);
        }
      }
    });

    // Try to get already connected devices
    _readerManager
        .connectedReaders()
        .then((devices) async {
          if (devices.isNotEmpty) {
            await _connectHinataReader(devices.first);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          log(
            'Failed to enumerate HID devices during init.',
            error: error,
            stackTrace: stackTrace,
          );
        });
  }

  Future<void> requestUsbDevice() async {
    state = state.copyWith(isConnecting: true, error: null);
    if (!_readerManager.isAvailable) {
      state = state.copyWith(
        isConnecting: false,
        error: 'USB HID is not available in this browser',
      );
      return;
    }

    try {
      final devices = await _readerManager.requestReaders();
      if (devices.isNotEmpty) {
        await _connectHinataReader(devices.first);
      } else {
        state = state.copyWith(
          isConnecting: false,
          error: 'No device selected',
        );
      }
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> _connectToHidDeviceWhenReady(HIDDevice device) async {
    final generation = ++_connectGeneration;
    state = state.copyWith(isConnecting: true, error: null);

    final reader = await _readerManager.waitUntilReady(
      device,
      shouldCancel: () => generation != _connectGeneration,
    );
    if (reader != null) {
      await _connectHinataReader(reader, generation: generation);
      return;
    }

    if (generation == _connectGeneration) {
      state = state.copyWith(
        isConnecting: false,
        error: 'HID device is not ready. Please reconnect the reader.',
      );
    }
  }

  Future<void> _connectHinataReader(
    HinataReader reader, {
    int? generation,
  }) async {
    generation ??= ++_connectGeneration;
    state = state.copyWith(isConnecting: true, error: null);
    try {
      await reader.connect();

      if (generation != _connectGeneration) {
        await reader.disconnect();
        return;
      }

      final firmVer = reader.firmVersion;
      final pid = reader.productId;

      state = state.copyWith(
        connectedDevice: reader,
        isConnecting: false,
        firmwareVersion: firmVer,
        productId: pid,
      );

      // Trigger background firmware status check immediately
      if (firmwareFeatureEnabled) {
        ref.read(firmwareProvider.notifier).requestFirmware(reader);
      }

      reader.connectionState.addListener(() {
        if (reader.connectionState.value ==
            ReaderConnectionState.disconnected) {
          // Check if we are currently updating to prevent state clearing
          final isUpdating = ref.read(firmwareProvider).isUpdating;
          if (state.connectedDevice == reader && !isUpdating) {
            state = state.copyWith(clearDevice: true);
          }
        }
      });
      _startPollLoop(reader);
    } catch (e, s) {
      if (generation != _connectGeneration) {
        return;
      }
      log('Failed to connect HID device.', error: e, stackTrace: s);
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> _startPollLoop(HinataReader reader) async {
    while (state.connectedDevice == reader) {
      if (!_readerManager.hasFocus) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        final scannedCard = await _pollReader(reader);

        if (scannedCard != null) {
          await ref
              .read(nfcProvider.notifier)
              .handleExternalScan(
                scannedCard,
                presenceMode: ScanPresenceMode.explicitRemoval,
              );
        } else {
          ref
              .read(currentScanSessionProvider.notifier)
              .markCardRemoved(source: 'HINATA');
        }
      } catch (e) {
        log("Polling error: $e");
        continue;
      }
    }

    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: 'HINATA');
  }

  Future<ScannedCard?> _pollReader(HinataReader reader) async {
    final cardTag = await reader.pollCard();
    if (cardTag == null) {
      _clearReadFailureState();
      return null;
    }

    final scannedCard = await CardReaderEngine(
      reader.createTransceiver(),
    ).processTag(cardTag, source: 'HINATA');

    return _resolveReaderScan(scannedCard);
  }

  ScannedCard? _resolveReaderScan(ScannedCard? scannedCard) {
    final card = scannedCard?.card;
    if (scannedCard == null || card is! InvalidMifareCard) {
      _clearReadFailureState();
      return scannedCard;
    }

    if (card.reason != InvalidMifareReason.readFailure) {
      _clearReadFailureState();
      return scannedCard;
    }

    final now = DateTime.now();
    final key = _readFailureKey(card);
    final confirmed = _confirmedReadFailure;
    if (confirmed != null && confirmed.key == key) {
      return confirmed.scannedCard;
    }

    final pending = _pendingReadFailure;
    if (pending == null || pending.key != key) {
      _pendingReadFailure = _PendingReadFailure(
        key: key,
        firstSeenAt: now,
        scannedCard: scannedCard,
      );
      return null;
    }

    if (now.difference(pending.firstSeenAt) < _readFailureConfirmWindow) {
      return null;
    }

    _pendingReadFailure = null;
    _confirmedReadFailure = pending;
    return pending.scannedCard;
  }

  String _readFailureKey(InvalidMifareCard card) {
    return '${card.idString}|${card.sak}|${card.atqa}'.toUpperCase();
  }

  void _clearReadFailureState() {
    _pendingReadFailure = null;
    _confirmedReadFailure = null;
  }

  void setIsUpdating(bool updating) {
    state = state.copyWith(isUpdating: updating);
  }

  void disconnect() async {
    _connectGeneration++;
    await state.connectedDevice?.disconnect();
    ref
        .read(currentScanSessionProvider.notifier)
        .markCardRemoved(source: 'HINATA');
    state = state.copyWith(clearDevice: true);
  }
}

final hardwareDeviceProvider =
    NotifierProvider<HardwareDeviceNotifier, HardwareDeviceState>(() {
      return HardwareDeviceNotifier();
    });

class _PendingReadFailure {
  const _PendingReadFailure({
    required this.key,
    required this.firstSeenAt,
    required this.scannedCard,
  });

  final String key;
  final DateTime firstSeenAt;
  final ScannedCard scannedCard;
}
