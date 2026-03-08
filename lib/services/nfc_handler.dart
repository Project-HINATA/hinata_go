import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:uuid/uuid.dart';

import '../models/card/scanned_card.dart';
import '../models/card/saved_card.dart';
import '../models/scan_log.dart';
import '../providers/app_state_provider.dart';
import '../navigation/router.dart';
import 'api_service.dart';
import 'nfc_service.dart';

class NfcState {
  final bool isScanning;
  final bool isProcessing;
  final String status;

  NfcState({
    this.isScanning = false,
    this.isProcessing = false,
    this.status = 'Ready to scan',
  });

  NfcState copyWith({bool? isScanning, bool? isProcessing, String? status}) {
    return NfcState(
      isScanning: isScanning ?? this.isScanning,
      isProcessing: isProcessing ?? this.isProcessing,
      status: status ?? this.status,
    );
  }
}

final nfcHandlerProvider = NotifierProvider<NfcHandler, NfcState>(() {
  return NfcHandler();
});

class NfcHandler extends Notifier<NfcState> {
  @override
  NfcState build() {
    return NfcState();
  }

  Future<void> startSession() async {
    if (state.isScanning) return;
    try {
      NfcAvailability availability = await NfcManager.instance
          .checkAvailability();
      if (availability == NfcAvailability.unsupported) {
        state = state.copyWith(status: 'Your device does not support NFC');
        return;
      }

      if (availability == NfcAvailability.disabled) {
        state = state.copyWith(status: 'Please enable NFC');
        return;
      }

      state = state.copyWith(isScanning: true, status: 'Listening for NFC...');

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso18092},
        onDiscovered: (NfcTag tag) async {
          await _onTagDiscovered(tag);
        },
      );
    } catch (e) {
      state = state.copyWith(isScanning: false, status: 'Error: $e');
    }
  }

  Future<void> stopSession() async {
    if (!state.isScanning) return;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    state = state.copyWith(isScanning: false, status: 'Stopped');
  }

  Future<void> _onTagDiscovered(NfcTag tag) async {
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

    // 3. Auto-send to active instance
    final activeInstance = ref.read(activeInstanceProvider);
    if (activeInstance != null) {
      final apiService = ref.read(apiServiceProvider);
      await apiService.sendCardData(
        instance: activeInstance,
        type: card.type ?? 'unknown',
        value: card.value ?? '',
      );
    }

    // 4. Navigate back to reader page if not there
    ref.read(routerProvider).go('/reader');
  }

  // Also expose for QR processing
  Future<void> handleExternalScan(ScannedCard scannedCard) async {
    await _processScannedCard(scannedCard);
  }
}
