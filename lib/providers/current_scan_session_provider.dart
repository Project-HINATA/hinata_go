import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/card/scanned_card.dart';
import '../models/card/transit.dart';

enum ScanPresenceMode { explicitRemoval, timeoutHeartbeat, immediate }

enum ScanRecordResult { accepted, duplicate }

class CurrentScanSessionState {
  final ScannedCard? scannedCard;
  final String? dedupeKey;
  final bool isCardPresent;
  final DateTime? lastAcceptedScanAt;
  final DateTime? cardRemovedAt;
  final ScanPresenceMode? presenceMode;
  final bool isReadingExtendedInfo;
  final bool isExtendedInfoLoaded;

  const CurrentScanSessionState({
    this.scannedCard,
    this.dedupeKey,
    this.isCardPresent = false,
    this.lastAcceptedScanAt,
    this.cardRemovedAt,
    this.presenceMode,
    this.isReadingExtendedInfo = false,
    this.isExtendedInfoLoaded = false,
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
    bool? isReadingExtendedInfo,
    bool? isExtendedInfoLoaded,
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
      isReadingExtendedInfo:
          isReadingExtendedInfo ?? this.isReadingExtendedInfo,
      isExtendedInfoLoaded: isExtendedInfoLoaded ?? this.isExtendedInfoLoaded,
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
  static const _pollMissesBeforeRemoval = 3;

  Timer? _presenceTimer;
  int _consecutivePresenceMisses = 0;

  @override
  CurrentScanSessionState build() {
    ref.onDispose(_cancelPresenceTimer);
    return const CurrentScanSessionState();
  }

  ScanRecordResult markCardPlaced(
    ScannedCard scannedCard, {
    ScanPresenceMode presenceMode = ScanPresenceMode.explicitRemoval,
    Duration heartbeatTimeout = _defaultHeartbeatTimeout,
  }) {
    return recordScan(
      scannedCard,
      presenceMode: presenceMode,
      heartbeatTimeout: heartbeatTimeout,
    );
  }

  ScanRecordResult recordScan(
    ScannedCard scannedCard, {
    required ScanPresenceMode presenceMode,
    Duration heartbeatTimeout = _defaultHeartbeatTimeout,
  }) {
    _consecutivePresenceMisses = 0;
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
      isExtendedInfoLoaded: scannedCard.isExtendedInfoFullyLoaded,
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

    _consecutivePresenceMisses = 0;
    _cancelPresenceTimer();
    state = state.copyWith(isCardPresent: false, cardRemovedAt: DateTime.now());
  }

  bool markCardMissing({String? source}) {
    if (!state.hasScan || !state.isCardPresent) return false;
    if (source != null && state.scannedCard!.source != source) return false;

    _consecutivePresenceMisses++;
    if (_consecutivePresenceMisses < _pollMissesBeforeRemoval) return false;

    markCardRemoved(source: source);
    return true;
  }

  void setReadingExtendedInfo(bool value) {
    state = state.copyWith(isReadingExtendedInfo: value);
  }

  void updateCard(ScannedCard updatedCard) {
    if (state.hasScan &&
        state.scannedCard!.card.idString == updatedCard.card.idString) {
      state = state.copyWith(
        scannedCard: updatedCard,
        isExtendedInfoLoaded: updatedCard.isExtendedInfoFullyLoaded,
      );
    }
  }

  void clear() {
    _consecutivePresenceMisses = 0;
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
    final cardNumber = card is TransitCard ? card.cardNumber : null;
    final cardIdentity = cardNumber != null && cardNumber.isNotEmpty
        ? cardNumber
        : (card.gamePayload ?? card.idString);
    final cardType = card.type ?? card.runtimeType.toString();
    return '${scannedCard.source}|$cardType|$cardIdentity'.toUpperCase();
  }
}
