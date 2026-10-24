import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../core/engine/type4_ndef_tag.dart';
import 'usb_hinata_impl.dart';

enum NdefEmulationEvent { waitingForPhone, phoneConnected, messageRead }

/// Presents a HINATA reader's PN532 as a read-only Type 4 NDEF tag.
///
/// Needs firmware that lets a new PN532 request replace a pending
/// `TgInitAsTarget`, and keeps card polling paused while one waits.
class HinataNdefEmulator {
  /// A HID report carries 62 PN532 bytes: `TgSetData` takes 9 of them, the
  /// status word 2 more.
  static const hidMaxRead = 51;

  static const ackTimeoutMs = 500;
  static const sendTimeoutMs = 500;

  /// Automatic RATS and ATR_RES, the PN532 defaults, plus ISO 14443-4 PICC
  /// emulation.
  static const _targetParameters = 0x34;
  static const _defaultParameters = 0x14;

  /// PICC-only, ATQA 04 00, SAK 20, with zeroed FeliCa and DEP parameters.
  static final _targetMode = Uint8List(37)
    ..setAll(0, const [0x05, 0x04, 0x00, 0x00, 0x00, 0x00, 0x20]);

  final Pn532Api _api;

  HinataNdefEmulator(this._api);

  /// Serves [message] until [cancel] completes. Waits for a phone, and for
  /// each of its commands, without a time limit.
  Future<void> run(
    Uint8List message, {
    required Future<void> cancel,
    required void Function(NdefEmulationEvent event) onEvent,
  }) async {
    final tag = Type4NdefTag(message, maxRead: hidMaxRead);
    var cancelled = false;
    unawaited(cancel.then((_) => cancelled = true));

    await _api.setParameters(_targetParameters);
    // Target inherits the RF configuration of the last polling profile; the
    // antenna is not tuned for emulation yet, so use the PN532 default.
    await _api.setTypeARfPower(
      rfCfg: pn532DefaultTypeARfProfile.rfCfg,
      cwGsNOn: pn532DefaultTypeARfProfile.cwGsNOn,
      cwGsP: pn532DefaultTypeARfProfile.cwGsP,
    );

    var waiting = false;
    try {
      while (!cancelled) {
        tag.reset();
        if (!waiting) {
          waiting = true;
          onEvent(NdefEmulationEvent.waitingForPhone);
        }
        try {
          final activation = await _api.tgInitAsTarget(
            _targetMode,
            ackTimeout: ackTimeoutMs,
            cancel: cancel,
          );
          // In PICC-only mode the PN532 has already answered RATS with ATS.
          if (activation.isEmpty || activation[0] & 0x08 == 0) continue;
          waiting = false;
          onEvent(NdefEmulationEvent.phoneConnected);

          while (!cancelled) {
            final command = await _api.tgGetData(
              ackTimeout: ackTimeoutMs,
              cancel: cancel,
            );
            await _api.tgSetData(
              tag.process(Uint8List.fromList(command)),
              timeout: sendTimeoutMs,
              ackTimeout: ackTimeoutMs,
            );
            if (tag.takeMessageRead()) {
              onEvent(NdefEmulationEvent.messageRead);
            }
          }
        } on Pn532CancelledException {
          break;
        } on Pn532StatusException {
          // The phone released the tag or the RF link broke.
        } on Exception catch (error, stackTrace) {
          log(
            'NDEF emulation session ended',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      await _restore();
    }
  }

  Future<void> _restore() async {
    try {
      // An ordinary request replaces a pending target command.
      await _api.getFirmwareVersion();
      await _api.setParameters(_defaultParameters);
    } catch (error, stackTrace) {
      log(
        'Failed to restore the PN532 after NDEF emulation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
