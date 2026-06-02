import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:uuid/uuid.dart';

import '../models/card/aime.dart';
import '../models/card/banapass.dart';
import '../models/card/invalid_mifare.dart';
import '../models/card/iso14443a.dart';
import '../models/card/scanned_card.dart';
import '../models/card/saved_card.dart';
import '../models/card/transit.dart';
import '../models/card/tunion.dart';
import '../models/scan_log.dart';
import '../navigation/router.dart';
import '../services/nfc_service.dart';
import '../services/notification_service.dart';
import 'card_sender.dart';
import 'app_state_provider.dart';
import 'current_scan_session_provider.dart';
import '../models/scanning_mode.dart';

enum NfcStatus { idle, tapToScan, unsupported, disabled, listening, error }

class NfcState {
  final bool isScanning;
  final bool isProcessing;
  final bool isIOS;
  final NfcStatus status;
  final DateTime? lastScanEvent;
  final String? errorMessage;

  NfcState({
    this.isScanning = false,
    this.isProcessing = false,
    this.isIOS = false,
    this.status = NfcStatus.idle,
    this.lastScanEvent,
    this.errorMessage,
  });

  NfcState copyWith({
    bool? isScanning,
    bool? isProcessing,
    bool? isIOS,
    NfcStatus? status,
    DateTime? lastScanEvent,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NfcState(
      isScanning: isScanning ?? this.isScanning,
      isProcessing: isProcessing ?? this.isProcessing,
      isIOS: isIOS ?? this.isIOS,
      status: status ?? this.status,
      lastScanEvent: lastScanEvent ?? this.lastScanEvent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final nfcProvider = NotifierProvider<NfcNotifier, NfcState>(() {
  return NfcNotifier();
});

class NfcNotifier extends Notifier<NfcState> with WidgetsBindingObserver {
  bool _isStarting = false;
  bool _isRetrying = false;
  String? _lastScanLogId;
  String? _lastSavedCardId;

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

    final isIOS = !kIsWeb && Platform.isIOS;
    if (!kIsWeb && Platform.isAndroid) {
      Future.microtask(() => startSession());
    }

    final initialStatus = kIsWeb
        ? NfcStatus.unsupported
        : (isIOS ? NfcStatus.tapToScan : NfcStatus.idle);

    return NfcState(isIOS: isIOS, status: initialStatus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NFC is global foreground-wide. Only auto-resume on Android.
    if (state == AppLifecycleState.resumed && !kIsWeb && Platform.isAndroid) {
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
        state = state.copyWith(status: NfcStatus.unsupported, clearError: true);
        return;
      }

      if (availability == NFCAvailability.disabled) {
        _isStarting = false;
        state = state.copyWith(status: NfcStatus.disabled, clearError: true);
        return;
      }

      _isStarting = false;
      state = state.copyWith(
        isScanning: true,
        status: NfcStatus.listening,
        clearError: true,
      );

      // iOS uses a system modal, so we typically do a single poll.
      // Android uses continuous background scanning.
      if (!kIsWeb && Platform.isIOS) {
        try {
          final iosAlert =
              ref.read(notificationServiceProvider).l10n?.nfcIosAlert ??
              'Hold your card near the top of your iPhone';
          NFCTag tag = await FlutterNfcKit.poll(
            iosAlertMessage: iosAlert,
            readIso18092: true,
            readIso14443B: false,
            readIso15693: true,
          );
          await _onTagDiscovered(tag);
        } catch (e) {
          log('iOS NFC poll error or cancel: $e');
        } finally {
          stopSession();
        }
      } else {
        // Android continuous loop or non-iOS platforms
        while (state.isScanning) {
          try {
            NFCTag tag = await FlutterNfcKit.poll(
              readIso18092: true,
              readIso14443B: false,
              readIso15693: true,
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
      state = state.copyWith(
        isScanning: false,
        status: NfcStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      if (state.isScanning && !kIsWeb && Platform.isAndroid) {
        stopSession();
      }
    }
  }

  Future<void> stopSession() async {
    state = state.copyWith(
      isScanning: false,
      status: state.isIOS ? NfcStatus.tapToScan : NfcStatus.idle,
      clearError: true,
    );
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
  }

  Future<void> _onTagDiscovered(NFCTag tag) async {
    if (state.isProcessing) return;
    state = state.copyWith(isProcessing: true);

    try {
      // 1. Read basic info first (extremely fast)
      final scannedCard = await handleNfcTag(tag, readExtended: false);

      // Dismiss the global processing indicator overlay immediately so UI can update
      state = state.copyWith(isProcessing: false);

      ScannedCard? finalCard = scannedCard;
      NFCTag activeTag = tag;

      // 2. FeliCa fallback: if the card is an unidentified ISO14443A tag
      //    (CPU card that failed T-Union, or unknown type), re-poll with
      //    FeliCa-only mode. This solves the issue where scanning an iPhone
      //    picks IsoDep instead of Suica's FeliCa interface.
      if (finalCard != null &&
          _isUnidentifiedIso14443(finalCard) &&
          !kIsWeb &&
          Platform.isAndroid &&
          !_isRetrying) {
        final retryResult = await _attemptFelicaRetry();
        if (retryResult != null) {
          finalCard = retryResult.$1;
          activeTag = retryResult.$2;
        }
      }

      if (finalCard != null) {
        await _registerScan(
          finalCard,
          presenceMode: ScanPresenceMode.timeoutHeartbeat,
        );

        // 3. If it is a transit card, read extended info sequentially if not yet loaded
        final sessionState = ref.read(currentScanSessionProvider);
        if (finalCard.card is TransitCard &&
            !sessionState.isReadingExtendedInfo &&
            !sessionState.isExtendedInfoLoaded) {
          ref
              .read(currentScanSessionProvider.notifier)
              .setReadingExtendedInfo(true);

          // Yield to Flutter to paint Phase 1 UI immediately
          await Future.delayed(const Duration(milliseconds: 50));

          try {
            final extendedCard = await handleNfcTag(
              activeTag,
              readExtended: true,
              existingCard: sessionState.scannedCard ?? finalCard,
            );
            if (extendedCard != null) {
              ref
                  .read(currentScanSessionProvider.notifier)
                  .updateCard(extendedCard);
              await _updateRegisteredScan(extendedCard);
            }
          } catch (e) {
            log('Error reading extended transit history: $e');
          } finally {
            ref
                .read(currentScanSessionProvider.notifier)
                .setReadingExtendedInfo(false);
          }
        }
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  /// Whether the scan result is an unidentified ISO14443A card.
  /// This includes plain [Iso14443] cards that were not recognized as any
  /// known subtype (T-Union, Aime, Banapass, etc.).
  /// [InvalidMifareCard] is excluded — that is a genuine Mifare Classic
  /// read failure and should not trigger a FeliCa retry.
  bool _isUnidentifiedIso14443(ScannedCard card) {
    final c = card.card;
    return c is Iso14443 &&
        c is! TUnion &&
        c is! Aime &&
        c is! Banapass &&
        c is! InvalidMifareCard;
  }

  /// Finish the current NFC session and re-poll with FeliCa-only tech flags.
  /// Returns the new [ScannedCard] and the [NFCTag] if FeliCa was found, or null on failure.
  Future<(ScannedCard, NFCTag)?> _attemptFelicaRetry() async {
    _isRetrying = true;
    bool success = false;
    try {
      await FlutterNfcKit.finish();

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 3),
        readIso14443A: false,
        readIso14443B: false,
        readIso18092: true,
        readIso15693: false,
      );

      final scannedCard = await handleNfcTag(tag, readExtended: false);
      if (scannedCard != null) {
        success = true;
        return (scannedCard, tag);
      }
      return null;
    } catch (e) {
      log('FeliCa retry failed: $e');
      return null;
    } finally {
      _isRetrying = false;
      if (!success) {
        try {
          await FlutterNfcKit.finish();
        } catch (_) {}
      }
    }
  }

  Future<void> _registerScan(
    ScannedCard scannedCard, {
    required ScanPresenceMode presenceMode,
  }) async {
    final result = ref
        .read(currentScanSessionProvider.notifier)
        .recordScan(scannedCard, presenceMode: presenceMode);

    if (result == ScanRecordResult.duplicate) {
      return;
    }

    await _processScannedCard(scannedCard);
  }

  Future<void> _processScannedCard(ScannedCard scannedCard) async {
    state = state.copyWith(lastScanEvent: DateTime.now());

    // Keep unusable cards visible in the current scan panel, but do not record
    // or transmit them.
    if (!scannedCard.isUsable) {
      ref.read(routerProvider).go('/scan');
      return;
    }

    final scanningMode = ref.read(scanningModeProvider);
    final card = scannedCard.card;

    final scanLogId = const Uuid().v4();
    final savedCardId = const Uuid().v4();
    _lastScanLogId = scanLogId;
    _lastSavedCardId = savedCardId;

    // 1. Create ScanLog
    final newLog = ScanLog(
      id: scanLogId,
      source: scannedCard.source,
      showValue: scannedCard.showValue,
      card: card,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    // 2. Auto-save to 'history_folder'
    final savedCard = SavedCard.fromScanned(
      scannedCard,
      id: savedCardId,
      folderId: 'history_folder',
    );
    ref.read(savedCardsProvider.notifier).addCard(savedCard);

    // 3. Handle according to Scanning Mode
    if (scanningMode == ScanningMode.sender) {
      // Sender Mode: Auto-send to active instance
      await ref.read(cardSenderProvider.notifier).sendCard(card);
    }

    // 4. Ensure focus is on Scan page
    ref.read(routerProvider).go('/scan');
  }

  Future<void> _updateRegisteredScan(ScannedCard extendedCard) async {
    final card = extendedCard.card;

    if (_lastScanLogId != null) {
      final logs = ref.read(scanLogsProvider);
      try {
        final existingLog = logs.firstWhere((e) => e.id == _lastScanLogId);
        final updatedLog = ScanLog(
          id: existingLog.id,
          source: existingLog.source,
          showValue: extendedCard.showValue,
          card: card,
          timestamp: existingLog.timestamp,
        );
        ref.read(scanLogsProvider.notifier).updateLog(updatedLog);
      } catch (_) {}
    }

    if (_lastSavedCardId != null) {
      final savedCards = ref.read(savedCardsProvider);
      try {
        final existingSaved = savedCards.firstWhere(
          (e) => e.id == _lastSavedCardId,
        );
        final updatedSaved = SavedCard(
          id: existingSaved.id,
          name: existingSaved.name,
          card: card,
          folderId: existingSaved.folderId,
          source: existingSaved.source,
        );
        ref.read(savedCardsProvider.notifier).updateCard(updatedSaved);
      } catch (_) {}
    }
  }

  // Also expose for external processing (like QR)
  Future<void> handleExternalScan(
    ScannedCard scannedCard, {
    ScanPresenceMode presenceMode = ScanPresenceMode.immediate,
  }) async {
    await _registerScan(scannedCard, presenceMode: presenceMode);
  }

  /// Expose helper to allow external readers (like HINATA USB) to update scan logs
  Future<void> updateExternalScan(ScannedCard extendedCard) async {
    await _updateRegisteredScan(extendedCard);
  }
}
