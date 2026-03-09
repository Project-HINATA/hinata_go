import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:uuid/uuid.dart';

import '../models/card/scanned_card.dart';
import '../models/card/saved_card.dart';
import '../models/scan_log.dart';
import '../navigation/router.dart';
import '../services/nfc_service.dart';
import 'card_sender.dart';
import 'app_state_provider.dart';
import 'settings_provider.dart';

class NfcState {
  final bool isScanning;
  final bool isProcessing;
  final String status;

  NfcState({
    this.isScanning = false,
    this.isProcessing = false,
    this.status = 'Idle',
  });

  NfcState copyWith({bool? isScanning, bool? isProcessing, String? status}) {
    return NfcState(
      isScanning: isScanning ?? this.isScanning,
      isProcessing: isProcessing ?? this.isProcessing,
      status: status ?? this.status,
    );
  }
}

final nfcProvider = NotifierProvider<NfcNotifier, NfcState>(() {
  return NfcNotifier();
});

class NfcNotifier extends Notifier<NfcState> with WidgetsBindingObserver {
  bool _isStarting = false;

  @override
  NfcState build() {
    // Listen to tagStream for tags relayed from Android Intents (App Launch)
    FlutterNfcKit.tagStream.listen((tag) {
      _onTagDiscovered(tag);
    });

    // Pulse the native side to relay the initial tag that launched the app
    if (!kIsWeb && Platform.isAndroid) {
      const methodChannel = MethodChannel('moe.neri.hinatago/nfc_launcher');
      methodChannel.invokeMethod('getInitialTag').catchError((e) {
        log('Error getting initial tag: $e');
      });
    }

    // Register as observer for global app lifecycle
    WidgetsBinding.instance.addObserver(this);

    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      stopSession();
    });

    // Start session initially only on Android. iOS requires manual trigger.
    if (Platform.isAndroid) {
      Future.microtask(() => startSession());
    } else {
      state = NfcState(status: 'Tap to Scan');
    }

    return NfcState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NFC is global foreground-wide. Only auto-resume on Android.
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      startSession();
    } else if (state == AppLifecycleState.paused) {
      stopSession();
    }
  }

  Future<void> startSession() async {
    if (state.isScanning || _isStarting) return;
    _isStarting = true;

    try {
      NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
      if (availability == NFCAvailability.not_supported) {
        _isStarting = false;
        state = state.copyWith(status: 'Your device does not support NFC');
        return;
      }

      if (availability == NFCAvailability.disabled) {
        _isStarting = false;
        state = state.copyWith(status: 'Please enable NFC');
        return;
      }

      _isStarting = false;
      state = state.copyWith(isScanning: true, status: 'Listening for NFC...');

      // iOS uses a system modal, so we typically do a single poll.
      // Android uses continuous background scanning.
      if (Platform.isIOS) {
        try {
          NFCTag tag = await FlutterNfcKit.poll(
            iosAlertMessage: 'Hold your card near the top of your iPhone',
            readIso18092: true,
            readIso14443B: false,
          );
          await _onTagDiscovered(tag);
        } catch (e) {
          log('iOS NFC poll error or cancel: $e');
        } finally {
          stopSession();
        }
      } else {
        // Android continuous loop
        while (state.isScanning) {
          try {
            NFCTag tag = await FlutterNfcKit.poll(
              readIso18092: true,
              readIso14443B: false,
            );
            await _onTagDiscovered(tag);
          } catch (e) {
            if (e.toString().contains('User Canceled') ||
                e.toString().contains('Session Timeout')) {
              break;
            }
          }
        }
      }
    } catch (e) {
      _isStarting = false;
      state = state.copyWith(isScanning: false, status: 'Error: $e');
    } finally {
      if (state.isScanning && Platform.isAndroid) {
        stopSession();
      }
    }
  }

  Future<void> stopSession() async {
    state = state.copyWith(
      isScanning: false,
      status: Platform.isIOS ? 'Tap to Scan' : 'Idle',
    );
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
  }

  Future<void> _onTagDiscovered(NFCTag tag) async {
    if (state.isProcessing) return;
    state = state.copyWith(isProcessing: true);

    try {
      final scannedCard = await handleNfcTag(tag);
      if (scannedCard != null) {
        await _processScannedCard(scannedCard);
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> _processScannedCard(ScannedCard scannedCard) async {
    final settings = ref.read(settingsProvider);
    final card = scannedCard.card;

    // 1. Create ScanLog
    final newLog = ScanLog(
      id: const Uuid().v4(),
      source: scannedCard.source,
      showValue: scannedCard.showValue,
      card: card,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    // 2. Auto-save to 'history_folder'
    final savedCard = SavedCard.fromScanned(
      scannedCard,
      id: const Uuid().v4(),
      folderId: 'history_folder',
    );
    ref.read(savedCardsProvider.notifier).addCard(savedCard);

    // 3. Handle according to settings
    if (settings.enableSecondaryConfirmation) {
      // Navigate to card detail page
      ref.read(routerProvider).push('/card_detail', extra: card);
      return;
    }

    // Auto-send to active instance
    await ref.read(cardSenderProvider.notifier).sendCard(card);

    // 4. Navigate back to reader page if not there
    // This ensures scanning on other pages (Settings, etc.) returns focus to the reader
    ref.read(routerProvider).go('/reader');
  }

  // Also expose for external processing (like QR)
  Future<void> handleExternalScan(ScannedCard scannedCard) async {
    await _processScannedCard(scannedCard);
  }
}
