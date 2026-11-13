import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:hinata_nfc/hinata_nfc.dart';

import '../../core/engine/card_emulation.dart';
import '../../core/engine/felica_tag.dart';
import '../../core/engine/mifare_classic_tag.dart';
import '../../core/engine/type4_ndef_tag.dart';
import 'usb_hinata_impl.dart';

enum CardEmulationEvent { waitingForReader, readerConnected, dataRead }

/// Presents a HINATA reader's PN532 as an [EmulationTarget]: a FeliCa card,
/// a MIFARE Classic 1K card, or for NDEF also a Type 4 tag over Type A.
///
/// Needs firmware that lets a new PN532 request replace a pending
/// `TgInitAsTarget`, and keeps card polling paused while one waits.
class HinataCardEmulator {
  /// A HID report carries 62 PN532 bytes: `TgSetData` takes 9 of them, the
  /// status word 2 more.
  static const hidMaxRead = 51;

  /// With firmware that splits PN532 frames over HID reports, one frame
  /// carries 253 `TgSetData` bytes, the status word 2 of them.
  static const longFrameMaxRead = 251;

  static const ackTimeoutMs = 500;
  static const sendTimeoutMs = 500;

  /// The PN532 reports neither a FeliCa reader leaving nor its field going
  /// away, so a FeliCa session ends after this long without a command.
  static const felicaIdleTimeoutMs = 500;

  /// A MIFARE Classic session ends after this long without an initiator
  /// command so a new anticollision cycle can re-enable hardware CRC.
  static const mifareIdleTimeoutMs = 2000;

  /// Automatic RATS and ATR_RES, the PN532 defaults, plus ISO 14443-4 PICC
  /// emulation.
  static const _targetParameters = 0x34;
  static const _mifareParameters = 0x00;
  static const _defaultParameters = 0x14;

  /// Passive only. Not PICC-only, which would refuse the first FeliCa
  /// command; a Type A reader still gets ISO 14443-4 through RATS.
  static const _passiveOnly = 0x01;

  static const _ciuMode = 0x6301;
  static const _txMode = 0x6302;
  static const _rxMode = 0x6303;
  static const _manualRcv = 0x630D;
  static const _bitFraming = 0x633D;

  final Pn532Api _api;

  HinataCardEmulator(this._api);

  /// Serves [target] until [cancel] completes. Waits for a reader without a
  /// time limit.
  ///
  /// The PN532 answers FeliCa polling by itself, so a reader that only polls
  /// reads the IDm without this ever reporting a connection.
  Future<void> run(
    EmulationTarget target, {
    required Future<void> cancel,
    required void Function(CardEmulationEvent event) onEvent,
  }) async {
    var cancelled = false;
    unawaited(cancel.then((_) => cancelled = true));

    final mifare = target.mifare;
    if (mifare != null) {
      try {
        await _runMifare(mifare, () => cancelled, cancel, onEvent);
      } finally {
        await _restore(mifare: true);
      }
      return;
    }

    final hasNdef = target.type4 != null;
    final felica = target.felica!;
    final systemCode = felica.activationSystemCode;
    final targetMode = Uint8List.fromList([
      _passiveOnly,
      if (hasNdef) ...[
        0x04, 0x00, // SENS_RES
        0x00, 0x00, 0x00, // NFCID1
        0x20, // SEL_RES: ISO 14443-4
      ] else ...[
        0x00, 0x00, // SENS_RES: no Type A 106k response
        0x00, 0x00, 0x00, // NFCID1
        0x00, // SEL_RES
      ],
      ...felica.idm,
      ...felica.pmm,
      systemCode >> 8, systemCode & 0xFF,
      ...List.filled(10, 0), // NFCID3
      0x00, // no general bytes
      0x00, // no historical bytes
    ]);

    await _api.setParameters(hasNdef ? _targetParameters : _defaultParameters);
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
        if (!waiting) {
          waiting = true;
          onEvent(CardEmulationEvent.waitingForReader);
        }
        try {
          final activation = await _api.tgInitAsTarget(
            targetMode,
            ackTimeout: ackTimeoutMs,
            cancel: cancel,
          );
          if (activation.isEmpty) continue;
          final mode = activation[0];
          final baud = (mode >> 4) & 0x07;
          final type4 = target.type4;
          final Future<void> Function() serve;
          if (mode & 0x08 != 0 && type4 != null) {
            // The PN532 has already answered RATS with ATS.
            serve = () => _serveType4(type4, () => cancelled, cancel, onEvent);
          } else if ((mode & 0x07 == 0x02) && (baud == 1 || baud == 2)) {
            // Only serve FeliCa at 212 kbps (1) or 424 kbps (2).
            serve = () => _serveFelica(
              felica,
              activation.sublist(1),
              () => cancelled,
              cancel,
              onEvent,
            );
          } else {
            continue;
          }
          waiting = false;
          onEvent(CardEmulationEvent.readerConnected);
          await serve();
        } on Pn532CancelledException {
          break;
        } on Pn532StatusException {
          // The reader released the card or the RF link broke.
        } on TimeoutException {
          // The FeliCa reader went quiet, or the PN532 did not acknowledge.
        } on Exception catch (error, stackTrace) {
          log(
            'Card emulation session ended',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      await _restore();
    }
  }

  Future<void> _runMifare(
    MifareClassicTag tag,
    bool Function() isCancelled,
    Future<void> cancel,
    void Function(CardEmulationEvent event) onEvent,
  ) async {
    final targetMode = Uint8List.fromList([
      _passiveOnly,
      0x04, 0x00, // SENS_RES
      ...tag.uid.sublist(1), // NFCID1 (PN532 forces uid[0] = 0x08)
      0x08, // SEL_RES: MIFARE Classic 1K
      ...List.filled(18, 0), // FeliCaParams (unused with ModeDetOff)
      ...List.filled(10, 0), // NFCID3
      0x00, // no general bytes
      0x00, // no historical bytes
    ]);

    await _api.setParameters(_mifareParameters);
    await _api.setTypeARfPower(
      rfCfg: pn532DefaultTypeARfProfile.rfCfg,
      cwGsNOn: pn532DefaultTypeARfProfile.cwGsNOn,
      cwGsP: pn532DefaultTypeARfProfile.cwGsP,
    );
    // CIU_Mode bit 2 (ModeDetOff): answer Type A only, never FeliCa.
    await _api.writeRegisters(const [(_ciuMode, 0x3F)]);

    var waiting = false;
    while (!isCancelled()) {
      if (!waiting) {
        waiting = true;
        onEvent(CardEmulationEvent.waitingForReader);
      }
      try {
        tag.reset();
        await _api.writeRegisters(const [
          (_txMode, 0x80),
          (_rxMode, 0x80),
          (_manualRcv, 0x00),
          (_bitFraming, 0x00),
        ]);
        final activation = await _api.tgInitAsTarget(
          targetMode,
          ackTimeout: ackTimeoutMs,
          cancel: cancel,
        );
        if (activation.length < 2 || (activation[0] & 0x07) != 0x00) continue;
        waiting = false;
        onEvent(CardEmulationEvent.readerConnected);
        await _serveMifare(
          tag,
          activation.sublist(1),
          isCancelled,
          cancel,
          onEvent,
        );
      } on Pn532CancelledException {
        break;
      } on Pn532StatusException {
        // The reader released the card or the RF link broke.
      } on TimeoutException {
        // The reader went quiet, or the PN532 did not acknowledge.
      } on Exception catch (error, stackTrace) {
        log(
          'Card emulation session ended',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _serveMifare(
    MifareClassicTag tag,
    List<int> first,
    bool Function() isCancelled,
    Future<void> cancel,
    void Function(CardEmulationEvent event) onEvent,
  ) async {
    var pendingRegisters = <(int, int)>[
      const (_txMode, 0x00),
      const (_rxMode, 0x00),
      const (_manualRcv, 0x10),
    ];
    var lastBits = 0;
    var response = tag.first(Uint8List.fromList(first));
    while (!isCancelled() && response != null) {
      final registers = <(int, int)>[
        ...pendingRegisters,
        if (response.lastBits != lastBits) (_bitFraming, response.lastBits),
      ];
      pendingRegisters = const [];
      lastBits = response.lastBits;
      await _api.writeRegistersAndRespondToInitiator(
        registers,
        response.raw,
        timeout: sendTimeoutMs,
        ackTimeout: ackTimeoutMs,
      );
      if (tag.takeMarkerRead()) onEvent(CardEmulationEvent.dataRead);
      final frame = await _api.tgGetInitiatorCommand(
        timeout: mifareIdleTimeoutMs,
        ackTimeout: ackTimeoutMs,
        cancel: cancel,
      );
      response = tag.handle(Uint8List.fromList(frame));
    }
  }

  Future<void> _serveType4(
    Type4NdefTag tag,
    bool Function() isCancelled,
    Future<void> cancel,
    void Function(CardEmulationEvent event) onEvent,
  ) async {
    tag.reset();
    while (!isCancelled()) {
      final command = await _api.tgGetData(
        ackTimeout: ackTimeoutMs,
        cancel: cancel,
      );
      await _api.tgSetData(
        tag.process(Uint8List.fromList(command)),
        timeout: sendTimeoutMs,
        ackTimeout: ackTimeoutMs,
      );
      if (tag.takeMessageRead()) onEvent(CardEmulationEvent.dataRead);
    }
  }

  /// [first] is the command that ended activation. FeliCa frames carry their
  /// own length byte, which the tag does not see.
  Future<void> _serveFelica(
    FelicaTag tag,
    List<int> first,
    bool Function() isCancelled,
    Future<void> cancel,
    void Function(CardEmulationEvent event) onEvent,
  ) async {
    var frame = first;
    while (!isCancelled()) {
      if (frame.isNotEmpty && frame[0] == frame.length) {
        final response = tag.process(
          Uint8List.sublistView(Uint8List.fromList(frame), 1),
        );
        if (response != null) {
          await _api.tgResponseToInitiator(
            [response.length + 1, ...response],
            timeout: sendTimeoutMs,
            ackTimeout: ackTimeoutMs,
          );
          if (tag.takeMarkerRead()) onEvent(CardEmulationEvent.dataRead);
        }
      }
      frame = await _api.tgGetInitiatorCommand(
        timeout: felicaIdleTimeoutMs,
        ackTimeout: ackTimeoutMs,
        cancel: cancel,
      );
    }
  }

  Future<void> _restore({bool mifare = false}) async {
    try {
      // An ordinary request replaces a pending target command.
      await _api.getFirmwareVersion();
      if (mifare) {
        await _api.writeRegisters(const [
          (_ciuMode, 0x3B),
          (_txMode, 0x80),
          (_rxMode, 0x80),
          (_manualRcv, 0x00),
          (_bitFraming, 0x00),
        ]);
      }
      await _api.setParameters(_defaultParameters);
    } catch (error, stackTrace) {
      log(
        'Failed to restore the PN532 after card emulation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
