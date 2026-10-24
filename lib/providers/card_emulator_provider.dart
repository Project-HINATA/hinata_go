import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/engine/type4_ndef_tag.dart';
import '../models/card/ndef.dart';
import '../models/card/saved_card.dart';
import '../services/reader/hinata_ndef_emulator.dart';
import 'hardware_device_provider.dart';

enum CardEmulatorStatus {
  idle,
  starting,
  waitingForPhone,
  phoneConnected,
  stopping,
  stopped,
  failed,
}

enum CardEmulatorFailure {
  noReader,
  unsupportedCard,
  readerDisconnected,
  failed,
}

class CardEmulatorState {
  final CardEmulatorStatus status;
  final int readCount;
  final CardEmulatorFailure? failure;

  const CardEmulatorState({
    this.status = CardEmulatorStatus.idle,
    this.readCount = 0,
    this.failure,
  });

  bool get isEmulating => switch (status) {
    CardEmulatorStatus.starting ||
    CardEmulatorStatus.waitingForPhone ||
    CardEmulatorStatus.phoneConnected ||
    CardEmulatorStatus.stopping => true,
    _ => false,
  };

  bool get canStop => isEmulating && status != CardEmulatorStatus.stopping;

  CardEmulatorState copyWith({
    CardEmulatorStatus? status,
    int? readCount,
    CardEmulatorFailure? failure,
  }) => CardEmulatorState(
    status: status ?? this.status,
    readCount: readCount ?? this.readCount,
    failure: failure ?? this.failure,
  );
}

/// The PN532 can emulate a tag only through a connected HINATA reader, and
/// iOS cannot drive one.
final cardEmulatorAvailableProvider = Provider<bool>((ref) {
  if (!kIsWeb && Platform.isIOS) return false;
  return ref.watch(hardwareDeviceProvider).connectedDevice != null;
});

final cardEmulatorProvider = NotifierProvider<CardEmulator, CardEmulatorState>(
  CardEmulator.new,
);

class CardEmulator extends Notifier<CardEmulatorState> {
  bool _stopRequested = false;
  Completer<void>? _cancel;
  Future<void>? _session;

  @override
  CardEmulatorState build() => const CardEmulatorState();

  /// Emulates [card] until [stop]; returns whether it ended without failure.
  Future<bool> emulate(SavedCard card) async {
    if (state.isEmulating) return false;
    state = const CardEmulatorState();

    final ndef = card.card;
    if (ndef is! NdefCard ||
        ndef.message.isEmpty ||
        ndef.message.length > Type4NdefTag.maxMessageSize) {
      return _fail(CardEmulatorFailure.unsupportedCard);
    }
    if (!ref.read(cardEmulatorAvailableProvider)) {
      return _fail(CardEmulatorFailure.noReader);
    }

    _stopRequested = false;
    final cancel = Completer<void>();
    _cancel = cancel;
    state = const CardEmulatorState(status: CardEmulatorStatus.starting);
    final session = Completer<void>();
    _session = session.future;
    final hardware = ref.read(hardwareDeviceProvider.notifier);
    ProviderSubscription<HardwareDeviceState>? connection;
    try {
      final reader = await hardware.suspendNfcPolling();
      if (reader == null) return _fail(CardEmulatorFailure.noReader);
      if (_stopRequested) return _finish();

      // Emulation waits for a phone without a time limit, so losing the
      // reader has to end it.
      connection = ref.listen(hardwareDeviceProvider, (_, next) {
        if (next.connectedDevice != reader && !cancel.isCompleted) {
          cancel.complete();
        }
      });
      if (ref.read(hardwareDeviceProvider).connectedDevice != reader) {
        return _fail(CardEmulatorFailure.readerDisconnected);
      }
      await reader.emulateNdef(
        ndef.message,
        cancel: cancel.future,
        onEvent: _onEvent,
      );
      if (!_stopRequested) {
        return _fail(CardEmulatorFailure.readerDisconnected);
      }
      return _finish();
    } catch (error, stackTrace) {
      log('NDEF emulation failed', error: error, stackTrace: stackTrace);
      if (_stopRequested) return _finish();
      return _fail(
        ref.read(hardwareDeviceProvider).connectedDevice == null
            ? CardEmulatorFailure.readerDisconnected
            : CardEmulatorFailure.failed,
      );
    } finally {
      connection?.close();
      hardware.resumeNfcPolling();
      _cancel = null;
      session.complete();
      _session = null;
    }
  }

  /// Stops emulation and waits until the reader is released.
  Future<void> stop() async {
    if (state.canStop) {
      _stopRequested = true;
      state = state.copyWith(status: CardEmulatorStatus.stopping);
      final cancel = _cancel;
      if (cancel != null && !cancel.isCompleted) cancel.complete();
    }
    await _session;
  }

  void _onEvent(NdefEmulationEvent event) {
    if (_stopRequested) return;
    state = switch (event) {
      NdefEmulationEvent.waitingForPhone => state.copyWith(
        status: CardEmulatorStatus.waitingForPhone,
      ),
      NdefEmulationEvent.phoneConnected => state.copyWith(
        status: CardEmulatorStatus.phoneConnected,
      ),
      NdefEmulationEvent.messageRead => state.copyWith(
        readCount: state.readCount + 1,
      ),
    };
  }

  bool _finish() {
    state = CardEmulatorState(
      status: CardEmulatorStatus.stopped,
      readCount: state.readCount,
    );
    return true;
  }

  bool _fail(CardEmulatorFailure failure) {
    state = CardEmulatorState(
      status: CardEmulatorStatus.failed,
      readCount: state.readCount,
      failure: failure,
    );
    return false;
  }
}
