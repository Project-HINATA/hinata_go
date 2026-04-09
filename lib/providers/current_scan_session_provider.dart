import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/card/scanned_card.dart';

enum ScanPresenceMode { explicitRemoval, timeoutHeartbeat, immediate }

enum ScanRecordResult { accepted, duplicate }

class CurrentScanSessionState {
  final ScannedCard? scannedCard;
  final String? dedupeKey;
  final bool isCardPresent;
  final DateTime? lastAcceptedScanAt;
  final DateTime? cardRemovedAt;
  final ScanPresenceMode? presenceMode;

  const CurrentScanSessionState({
    this.scannedCard,
    this.dedupeKey,
    this.isCardPresent = false,
    this.lastAcceptedScanAt,
    this.cardRemovedAt,
    this.presenceMode,
  });

  bool get hasScan => scannedCard != null;

  bool get showDismissControls => hasScan && !isCardPresent;

  CurrentScanSessionState copyWith({
    ScannedCard? scannedCard,
    String? dedupeKey,
    bool? isCardPresent,
    DateTime? lastAcceptedScanAt,
    DateTime? cardRemovedAt,
    ScanPresenceMode? presenceMode,
    bool clear = false,
    bool clearRemovedAt = false,
  }) {
    if (clear) {
      return const CurrentScanSessionState();
    }

    return CurrentScanSessionState(
      scannedCard: scannedCard ?? this.scannedCard,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      isCardPresent: isCardPresent ?? this.isCardPresent,
      lastAcceptedScanAt: lastAcceptedScanAt ?? this.lastAcceptedScanAt,
      cardRemovedAt: clearRemovedAt
          ? null
          : (cardRemovedAt ?? this.cardRemovedAt),
      presenceMode: presenceMode ?? this.presenceMode,
    );
  }
}

final currentScanSessionProvider =
    NotifierProvider<CurrentScanSessionNotifier, CurrentScanSessionState>(() {
      return CurrentScanSessionNotifier();
    });

final currentScanResultProvider = Provider<ScannedCard?>((ref) {
  return ref.watch(currentScanSessionProvider).scannedCard;
});

class CurrentScanSessionNotifier extends Notifier<CurrentScanSessionState> {
  static const _defaultHeartbeatTimeout = Duration(milliseconds: 1500);

  Timer? _presenceTimer;

  @override
  CurrentScanSessionState build() {
    ref.onDispose(_cancelPresenceTimer);
    return const CurrentScanSessionState();
  }

  ScanRecordResult recordScan(
    ScannedCard scannedCard, {
    required ScanPresenceMode presenceMode,
    Duration heartbeatTimeout = _defaultHeartbeatTimeout,
  }) {
    final dedupeKey = _buildDedupeKey(scannedCard);
    final isDuplicateWhilePresent =
        state.isCardPresent && state.dedupeKey == dedupeKey;

    if (isDuplicateWhilePresent) {
      _refreshPresence(
        dedupeKey: dedupeKey,
        presenceMode: presenceMode,
        heartbeatTimeout: heartbeatTimeout,
      );
      return ScanRecordResult.duplicate;
    }

    final acceptedAt = DateTime.now();
    final isCardPresent = presenceMode != ScanPresenceMode.immediate;

    _cancelPresenceTimer();
    state = CurrentScanSessionState(
      scannedCard: scannedCard,
      dedupeKey: dedupeKey,
      isCardPresent: isCardPresent,
      lastAcceptedScanAt: acceptedAt,
      cardRemovedAt: isCardPresent ? null : acceptedAt,
      presenceMode: presenceMode,
    );

    _refreshPresence(
      dedupeKey: dedupeKey,
      presenceMode: presenceMode,
      heartbeatTimeout: heartbeatTimeout,
    );
    return ScanRecordResult.accepted;
  }

  void markCardRemoved({String? source}) {
    if (!state.hasScan || !state.isCardPresent) return;
    if (source != null && state.scannedCard!.source != source) return;

    _cancelPresenceTimer();
    state = state.copyWith(isCardPresent: false, cardRemovedAt: DateTime.now());
  }

  void clear() {
    _cancelPresenceTimer();
    state = state.copyWith(clear: true);
  }

  void _refreshPresence({
    required String dedupeKey,
    required ScanPresenceMode presenceMode,
    required Duration heartbeatTimeout,
  }) {
    switch (presenceMode) {
      case ScanPresenceMode.explicitRemoval:
        _cancelPresenceTimer();
        state = state.copyWith(
          isCardPresent: true,
          presenceMode: presenceMode,
          clearRemovedAt: true,
        );
      case ScanPresenceMode.timeoutHeartbeat:
        _cancelPresenceTimer();
        state = state.copyWith(
          isCardPresent: true,
          presenceMode: presenceMode,
          clearRemovedAt: true,
        );
        _presenceTimer = Timer(heartbeatTimeout, () {
          if (state.dedupeKey == dedupeKey && state.isCardPresent) {
            markCardRemoved();
          }
        });
      case ScanPresenceMode.immediate:
        _cancelPresenceTimer();
        state = state.copyWith(
          isCardPresent: false,
          cardRemovedAt: state.cardRemovedAt ?? DateTime.now(),
          presenceMode: presenceMode,
        );
    }
  }

  void _cancelPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  String _buildDedupeKey(ScannedCard scannedCard) {
    final card = scannedCard.card;
    final cardIdentity = card.value ?? card.idString;
    final cardType = card.type ?? card.runtimeType.toString();
    return '${scannedCard.source}|$cardType|$cardIdentity'.toUpperCase();
  }
}
