import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:hinata_nfc/hinata_nfc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/engine/mifare_write_payload.dart';
import '../core/engine/nfc_tag_converter.dart';
import '../l10n/l10n.dart';
import '../models/card/card.dart';
import '../models/card/iso14443a.dart';
import '../models/card/ndef.dart';
import '../models/card/saved_card.dart';
import '../services/nfc/mifare_card_writer.dart';
import '../services/nfc/ndef_tag_service.dart';
import '../services/nfc/phone_ndef_service.dart';
import '../services/notification_service.dart';
import '../services/reader/usb_hinata_impl.dart';
import 'hardware_device_provider.dart';
import 'nfc_provider.dart';

enum CardWriterStatus { idle, waitingForCard, writing, success, failure }

class CardWriterState {
  final CardWriterStatus status;
  final MifareWriteStage? stage;
  final MifareWriteFailure? failure;

  const CardWriterState({
    this.status = CardWriterStatus.idle,
    this.stage,
    this.failure,
  });

  bool get isWriting =>
      status == CardWriterStatus.waitingForCard ||
      status == CardWriterStatus.writing;

  bool get canCancel =>
      status == CardWriterStatus.waitingForCard ||
      (status == CardWriterStatus.writing &&
          (stage == MifareWriteStage.checkingCard ||
              stage == MifareWriteStage.checkingPermissions));
}

final cardWriterAvailableProvider = Provider<bool>((ref) {
  if (!kIsWeb && Platform.isIOS) return false;
  final hasAndroidNfc = !kIsWeb && Platform.isAndroid;
  final hasReader = ref.watch(hardwareDeviceProvider).connectedDevice != null;
  return hasAndroidNfc || hasReader;
});

final ndefWriterAvailableProvider = Provider<bool>((ref) {
  return (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) ||
      ref.watch(hardwareDeviceProvider).connectedDevice != null;
});

final cardWriterProvider = NotifierProvider<CardWriter, CardWriterState>(() {
  return CardWriter();
});

class CardWriter extends Notifier<CardWriterState> {
  _AcquisitionCancellation? _activeAcquisition;
  bool _cancelRequested = false;

  @override
  CardWriterState build() => const CardWriterState();

  Future<bool> writeCard(SavedCard card, CardWriteMode mode) async {
    if (state.isWriting) return false;

    final notification = ref.read(notificationServiceProvider);
    final isNdef = card.card is NdefCard;
    MifareCardWritePayload? payload;
    try {
      if (!isNdef) payload = MifareCardWritePayload.fromCard(card.card, mode);
    } catch (error, stackTrace) {
      log(
        'Failed to build a MIFARE card write payload',
        error: error,
        stackTrace: stackTrace,
      );
      notification.showError(l10n.cardWriteUnsupportedSavedCard);
      return false;
    }

    if (!ref.read(
      isNdef ? ndefWriterAvailableProvider : cardWriterAvailableProvider,
    )) {
      notification.showError(
        isNdef ? l10n.ndefNoBackend : l10n.cardWriteNoBackend,
      );
      return false;
    }

    state = const CardWriterState(status: CardWriterStatus.waitingForCard);
    _WriteTarget? target;
    UsbHinataDeviceImpl? reader;
    try {
      _cancelRequested = false;
      await ref.read(nfcProvider.notifier).suspendForExclusiveOperation();
      reader = await ref
          .read(hardwareDeviceProvider.notifier)
          .suspendNfcPolling();

      if (_cancelRequested) {
        throw const MifareCardWriteException(
          MifareWriteFailure.cancelled,
          'Card writing was cancelled before target acquisition',
        );
      }
      target = await _acquireFirstTarget(reader, ndef: isNdef);

      void onStage(MifareWriteStage stage) {
        state = CardWriterState(status: CardWriterStatus.writing, stage: stage);
      }

      final targetTag = target.tag;
      if (card.card case final NdefCard ndefCard) {
        final phoneTag = target.phoneTag;
        final rawWritable =
            targetTag is Iso14443 &&
            (targetTag.sak == 0 || targetTag.isMifareClassicCandidate);
        if (phoneTag != null && (Platform.isIOS || !rawWritable)) {
          await writePhoneNdef(
            phoneTag,
            ndefCard,
            onStage: onStage,
            isCancelled: () => _cancelRequested,
            readOnly: mode == CardWriteMode.permanentlyReadOnly,
          );
        } else if (targetTag is Iso14443) {
          await NdefTagService(target.channel).write(
            targetTag,
            ndefCard,
            isCancelled: () => _cancelRequested,
            onStage: onStage,
            readOnly: mode == CardWriteMode.permanentlyReadOnly,
          );
        } else {
          throw const MifareCardWriteException(
            MifareWriteFailure.unsupportedCard,
            'Unsupported NDEF target',
          );
        }
      } else if (targetTag is Iso14443) {
        await MifareCardWriter(channel: target.channel, tag: targetTag).write(
          payload!,
          isCancelled: () => _cancelRequested,
          onStage: onStage,
        );
      } else {
        throw const MifareCardWriteException(
          MifareWriteFailure.unsupportedCard,
          'Not a Classic card',
        );
      }

      state = const CardWriterState(status: CardWriterStatus.success);
      notification.showSuccess(l10n.cardWriteSuccess);
      return true;
    } on MifareCardWriteException catch (error) {
      state = CardWriterState(
        status: CardWriterStatus.failure,
        failure: error.failure,
      );
      if (error.failure == MifareWriteFailure.cancelled) {
        notification.showInfo(l10n.cardWriteCancelled);
      } else {
        notification.showError(_localizedFailure(error.failure, ndef: isNdef));
      }
      return false;
    } catch (error, stackTrace) {
      log(
        'Unexpected card writing failure',
        error: error,
        stackTrace: stackTrace,
      );
      state = const CardWriterState(
        status: CardWriterStatus.failure,
        failure: MifareWriteFailure.writeFailed,
      );
      notification.showError(l10n.cardWriteFailed);
      return false;
    } finally {
      try {
        await target?.channel.close();
      } catch (_) {}
      ref.read(hardwareDeviceProvider.notifier).resumeNfcPolling();
      ref.read(nfcProvider.notifier).resumeAfterExclusiveOperation();
      _activeAcquisition = null;
    }
  }

  void reset() {
    if (!state.isWriting) state = const CardWriterState();
  }

  void cancel() {
    if (!state.canCancel) return;
    _cancelRequested = true;
    _activeAcquisition?.cancelled = true;
    if (state.status == CardWriterStatus.waitingForCard) {
      unawaited(() async {
        try {
          await FlutterNfcKit.finish();
        } catch (_) {}
      }());
    }
  }

  Future<_WriteTarget> _acquireFirstTarget(
    UsbHinataDeviceImpl? reader, {
    bool ndef = false,
  }) async {
    final cancellation = _AcquisitionCancellation();
    _activeAcquisition = cancellation;
    final sources = <Future<_WriteTarget>>[];
    if (!kIsWeb && (Platform.isAndroid || (ndef && Platform.isIOS))) {
      sources.add(_acquirePhoneTarget(cancellation, ndef: ndef));
    }
    if (reader != null) {
      sources.add(_acquireReaderTarget(reader, cancellation));
    }
    if (sources.isEmpty) {
      throw const MifareCardWriteException(
        MifareWriteFailure.unsupportedCard,
        'No card writer is available',
      );
    }

    _WriteTarget? target;
    try {
      target = await Future.any(sources).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw const MifareCardWriteException(
          MifareWriteFailure.cardRemoved,
          'Timed out waiting for a card',
        ),
      );
      return target;
    } finally {
      cancellation.cancelled = true;
      if (target?.backend != _WriteBackend.phone) {
        try {
          await FlutterNfcKit.finish();
        } catch (_) {}
      }
    }
  }

  Future<_WriteTarget> _acquirePhoneTarget(
    _AcquisitionCancellation cancellation, {
    bool ndef = false,
  }) async {
    while (!cancellation.cancelled) {
      try {
        final rawTag = await FlutterNfcKit.poll(
          readIso18092: ndef,
          readIso14443A: true,
          readIso14443B: false,
          readIso15693: ndef,
        );
        final tag =
            rawTag.toInternalTag() ??
            (ndef
                ? ICCard(
                    rawTag.id == 'unknown'
                        ? Uint8List(0)
                        : ICCard.hexToBytes(rawTag.id),
                  )
                : null);
        if (tag is Iso14443 || (ndef && tag is ICCard)) {
          if (cancellation.cancelled) break;
          return _WriteTarget(
            backend: _WriteBackend.phone,
            tag: tag as ICCard,
            phoneTag: rawTag,
            channel: PhoneNfcCardChannel(),
          );
        }
      } catch (_) {
        if (cancellation.cancelled) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    throw const MifareCardWriteException(
      MifareWriteFailure.cancelled,
      'Phone card acquisition was cancelled',
    );
  }

  Future<_WriteTarget> _acquireReaderTarget(
    UsbHinataDeviceImpl reader,
    _AcquisitionCancellation cancellation,
  ) async {
    while (!cancellation.cancelled) {
      try {
        final target = await reader.pollMifareTarget();
        if (target != null) {
          if (cancellation.cancelled) {
            await target.channel.close();
            break;
          }
          return _WriteTarget(
            backend: _WriteBackend.reader,
            tag: target.tag,
            channel: target.channel,
          );
        }
      } catch (_) {
        if (cancellation.cancelled) break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw const MifareCardWriteException(
      MifareWriteFailure.cancelled,
      'Reader card acquisition was cancelled',
    );
  }

  String _localizedFailure(MifareWriteFailure failure, {bool ndef = false}) =>
      switch (failure) {
        MifareWriteFailure.capacityExceeded => l10n.ndefCapacityExceeded,
        MifareWriteFailure.unsupportedCard =>
          ndef ? l10n.ndefUnsupportedTarget : l10n.cardWriteUnsupportedTarget,
        MifareWriteFailure.authenticationFailed => l10n.cardWriteUnknownKey,
        MifareWriteFailure.invalidAccessBits => l10n.cardWriteInvalidAccessBits,
        MifareWriteFailure.permissionDenied => l10n.cardWritePermissionDenied,
        MifareWriteFailure.lockUnsupported => l10n.ndefLockUnsupported,
        MifareWriteFailure.cardRemoved => l10n.cardWriteCardRemoved,
        MifareWriteFailure.verificationFailed =>
          l10n.cardWriteVerificationFailed,
        MifareWriteFailure.writeFailed => l10n.cardWriteFailed,
        MifareWriteFailure.cancelled => l10n.cardWriteCancelled,
      };
}

enum _WriteBackend { phone, reader }

class _WriteTarget {
  final _WriteBackend backend;
  final ICCard tag;
  final NFCTag? phoneTag;
  final NfcCardChannel channel;

  const _WriteTarget({
    required this.backend,
    required this.tag,
    this.phoneTag,
    required this.channel,
  });
}

class _AcquisitionCancellation {
  bool cancelled = false;
}
