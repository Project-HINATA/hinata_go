import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/engine/card_emulation.dart';
import '../models/card/saved_card.dart';
import '../services/reader/hinata_card_emulator.dart';
import 'hardware_device_provider.dart';

enum CardEmulatorStatus {
  idle,
  starting,
  waitingForReader,
  readerConnected,
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
  final EmulationKind? kind;
  final int readCount;
  final CardEmulatorFailure? failure;

  const CardEmulatorState({
    this.status = CardEmulatorStatus.idle,
    this.kind,
    this.readCount = 0,
    this.failure,
  });

  bool get isEmulating => switch (status) {
    CardEmulatorStatus.starting ||
    CardEmulatorStatus.waitingForReader ||
    CardEmulatorStatus.readerConnected ||
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
    kind: kind,
    readCount: readCount ?? this.readCount,
    failure: failure ?? this.failure,
  );
}

/// The PN532 can emulate a card only through a connected HINATA reader, and
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
    final kind = emulationKindOf(card.card);
    state = CardEmulatorState(kind: kind);
    if (kind == null) return _fail(CardEmulatorFailure.unsupportedCard);
    final target = emulationTargetFor(
      card.card,
      type4MaxRead: HinataCardEmulator.hidMaxRead,
    );
    if (!ref.read(cardEmulatorAvailableProvider)) {
      return _fail(CardEmulatorFailure.noReader);
    }

    _stopRequested = false;
    final cancel = Completer<void>();
    _cancel = cancel;
    state = CardEmulatorState(status: CardEmulatorStatus.starting, kind: kind);
    final session = Completer<void>();
    _session = session.future;
    final hardware = ref.read(hardwareDeviceProvider.notifier);
    ProviderSubscription<HardwareDeviceState>? connection;
    try {
      final reader = await hardware.suspendNfcPolling();
      if (reader == null) return _fail(CardEmulatorFailure.noReader);
      if (_stopRequested) return _finish();

      // Emulation waits for a reader without a time limit, so losing the
      // reader has to end it.
      connection = ref.listen(hardwareDeviceProvider, (_, next) {
        if (next.connectedDevice != reader && !cancel.isCompleted) {
          cancel.complete();
        }
      });
      if (ref.read(hardwareDeviceProvider).connectedDevice != reader) {
        return _fail(CardEmulatorFailure.readerDisconnected);
      }
      await reader.emulateCard(
        target,
        cancel: cancel.future,
        onEvent: _onEvent,
      );
      if (!_stopRequested) {
        return _fail(CardEmulatorFailure.readerDisconnected);
      }
      return _finish();
    } catch (error, stackTrace) {
      log('Card emulation failed', error: error, stackTrace: stackTrace);
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

  void _onEvent(CardEmulationEvent event) {
    if (_stopRequested) return;
    state = switch (event) {
      CardEmulationEvent.waitingForReader => state.copyWith(
        status: CardEmulatorStatus.waitingForReader,
      ),
      CardEmulationEvent.readerConnected => state.copyWith(
        status: CardEmulatorStatus.readerConnected,
      ),
      CardEmulationEvent.dataRead => state.copyWith(
        readCount: state.readCount + 1,
      ),
    };
  }

  bool _finish() {
    state = CardEmulatorState(
      status: CardEmulatorStatus.stopped,
      kind: state.kind,
      readCount: state.readCount,
    );
    return true;
  }

  bool _fail(CardEmulatorFailure failure) {
    state = CardEmulatorState(
      status: CardEmulatorStatus.failed,
      kind: state.kind,
      readCount: state.readCount,
      failure: failure,
    );
    return false;
  }
}
