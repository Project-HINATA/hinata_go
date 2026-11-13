import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/core/crypto/crypto1.dart';
import 'package:hinata_go/core/crypto/mifare_key.dart';
import 'package:hinata_go/core/engine/card_emulation.dart';
import 'package:hinata_go/core/engine/felica_tag.dart';
import 'package:hinata_go/core/engine/type3_ndef_tag.dart';
import 'package:hinata_go/core/engine/type4_ndef_tag.dart';
import 'package:hinata_go/models/card/aime.dart';
import 'package:hinata_go/models/card/iso14443a.dart';
import 'package:hinata_go/services/reader/hinata_card_emulator.dart';
import 'package:hinata_nfc/hinata_nfc.dart';

const _ack = [0, 0, 0xFF, 0, 0xFF, 0];

List<int> _response(int command, List<int> payload) {
  final body = [0xD5, command + 1, ...payload];
  final checksum = -body.fold<int>(0, (sum, b) => sum + b) & 0xFF;
  return [0, 0, 0xFF, body.length, -body.length & 0xFF, ...body, checksum, 0];
}

/// A PN532 whose replies to each command come from [respond]; a `null` reply
/// is acknowledged but never answered, like a target nobody activates.
class _ScriptedPn532 {
  final List<int>? Function(int command, List<int> payload) respond;
  final requests = <(int, List<int>)>[];

  /// The timeout of every read made after a command's ACK.
  final responseTimeouts = <(int, Duration?)>[];
  final _frames = Queue<List<int>>();

  _ScriptedPn532(this.respond);

  late final api = Pn532Api(
    (frame) async {
      final payload = frame.sublist(7, 5 + frame[3]);
      requests.add((frame[6], payload));
      _frames
        ..clear()
        ..add(_ack);
      final reply = respond(frame[6], payload);
      if (reply != null) _frames.add(_response(frame[6], reply));
    },
    ({timeout}) {
      if (_frames.isEmpty || !identical(_frames.first, _ack)) {
        responseTimeouts.add((requests.last.$1, timeout));
      }
      if (_frames.isNotEmpty) return Future.value(_frames.removeFirst());
      if (timeout == null) return Completer<List<int>>().future;
      return Future.error(TimeoutException('no frame', timeout));
    },
  );

  Iterable<int> get commands => requests.map((r) => r.$1);
}

final idm = Uint8List.fromList([0x02, 0xFE, 1, 2, 3, 4, 5, 6]);
final message = Uint8List.fromList([
  0xD1, 0x01, 0x04, 0x55, 0x04, 0x61, 0x2E, 0x62, //
]);

EmulationTarget ndefTarget() => EmulationTarget(
  kind: EmulationKind.ndef,
  type4: Type4NdefTag(message, maxRead: HinataCardEmulator.hidMaxRead),
  felica: Type3NdefTag(message, idm: idm),
);

void main() {
  test('serves the message to a phone, then waits for the next one', () async {
    final apdus = Queue<List<int>>.of([
      [0x00, 0xA4, 0x04, 0x00, 0x07, 0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01],
      [0x00, 0xA4, 0x00, 0x0C, 0x02, 0xE1, 0x04],
      [0x00, 0xB0, 0x00, 0x00, 0x02],
      [0x00, 0xB0, 0x00, 0x02, 0x08],
    ]);
    final responses = <List<int>>[];
    final events = <CardEmulationEvent>[];
    final cancel = Completer<void>();
    var targets = 0;

    final pn532 = _ScriptedPn532((command, payload) {
      switch (command) {
        case 0x02:
          return [0x32, 0x01, 0x06, 0x07];
        case 0x8C:
          if (++targets == 1) return [0x08, 0xE0, 0x80];
          // Nobody comes back; the wait ends only when cancelled.
          Timer(Duration.zero, cancel.complete);
          return null;
        case 0x86:
          return apdus.isEmpty ? [0x29] : [0x00, ...apdus.removeFirst()];
        case 0x8E:
          responses.add(payload);
          return [0x00];
        default:
          return [];
      }
    });

    await HinataCardEmulator(
      pn532.api,
    ).run(ndefTarget(), cancel: cancel.future, onEvent: events.add);

    expect(events, [
      CardEmulationEvent.waitingForReader,
      CardEmulationEvent.readerConnected,
      CardEmulationEvent.dataRead,
      CardEmulationEvent.waitingForReader,
    ]);
    expect(responses, [
      [0x90, 0x00],
      [0x90, 0x00],
      [0x00, 0x08, 0x90, 0x00],
      [...message, 0x90, 0x00],
    ]);

    expect(pn532.requests[0].$1, 0x12);
    expect(pn532.requests[0].$2, [0x34]);
    expect(pn532.requests[1].$1, 0x32);
    expect(pn532.requests[1].$2, [
      0x0A, 0x59, 0xF4, 0x3F, 0x11, 0x4D, 0x85, 0x61, 0x6F, 0x26, 0x62, 0x87, //
    ]);
    // The PN532 default is written once, not before every Target.
    expect(pn532.commands.where((c) => c == 0x32), hasLength(1));

    final target = pn532.requests.firstWhere((r) => r.$1 == 0x8C).$2;
    expect(target.length, 37);
    expect(target.sublist(0, 7), [0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x20]);
    // FeliCa polling gets a Type 3 NDEF tag rather than an all-zero card.
    expect(target.sublist(7, 25), [
      ...idm,
      ...List.filled(8, 0xFF),
      0x12,
      0xFC,
    ]);

    // Waiting for the phone, and for its next command, has no time limit.
    final waits = pn532.responseTimeouts.where(
      (r) => r.$1 == 0x8C || r.$1 == 0x86,
    );
    expect(waits, isNotEmpty);
    expect(waits.map((r) => r.$2), everyElement(isNull));

    // A plain request replaces the pending Target before parameters return
    // to the PN532 defaults.
    expect(pn532.commands.toList().reversed.take(3), [0x12, 0x02, 0x8C]);
    expect(pn532.requests.last.$2, [0x14]);
  });

  test('serves the message to a FeliCa phone as a Type 3 tag', () async {
    List<int> check(List<int> blocks) {
      final body = [
        0x06,
        ...idm,
        0x01,
        0x0B,
        0x00,
        blocks.length,
        for (final block in blocks) ...[0x80, block],
      ];
      return [body.length + 1, ...body];
    }

    final commands = Queue<List<int>>.of([
      check([1]),
    ]);
    final responses = <List<int>>[];
    final events = <CardEmulationEvent>[];
    final cancel = Completer<void>();
    var targets = 0;

    final pn532 = _ScriptedPn532((command, payload) {
      switch (command) {
        case 0x02:
          return [0x32, 0x01, 0x06, 0x07];
        case 0x8C:
          // Activated at 212 kbps with FeliCa framing.
          if (++targets == 1) {
            return [
              0x12,
              ...check([0]),
            ];
          }
          Timer(Duration.zero, cancel.complete);
          return null;
        case 0x88:
          // After the last command the phone goes quiet.
          return commands.isEmpty ? null : [0x00, ...commands.removeFirst()];
        case 0x90:
          responses.add(payload);
          return [0x00];
        default:
          return [];
      }
    });

    await HinataCardEmulator(
      pn532.api,
    ).run(ndefTarget(), cancel: cancel.future, onEvent: events.add);

    expect(events, [
      CardEmulationEvent.waitingForReader,
      CardEmulationEvent.readerConnected,
      CardEmulationEvent.dataRead,
      CardEmulationEvent.waitingForReader,
    ]);
    expect(responses, hasLength(2));
    expect(responses[0].sublist(0, 13), [29, 0x07, ...idm, 0, 0, 1]);
    expect(responses[0].sublist(13, 15), [0x10, 2]);
    expect(responses[1], [
      29,
      0x07,
      ...idm,
      0,
      0,
      1,
      ...message,
      ...List.filled(8, 0),
    ]);

    // The FeliCa session ends when the phone stays quiet for a while.
    final idle = pn532.responseTimeouts.where((r) => r.$1 == 0x88);
    expect(
      idle.map((r) => r.$2),
      everyElement(
        const Duration(milliseconds: HinataCardEmulator.felicaIdleTimeoutMs),
      ),
    );
    expect(pn532.requests.last.$2, [0x14]);
  });

  test(
    'a FeliCa card without NDEF uses zero Mifare params and default config, ignoring 106k',
    () async {
      final cardIdm = Uint8List.fromList([0x01, 0x2E, 1, 2, 3, 4, 5, 6]);
      final pmm = Uint8List.fromList([0x00, 0xF1, 0, 0, 0, 0x01, 0x43, 0]);
      final target = EmulationTarget(
        kind: EmulationKind.felica,
        felica: FelicaTag(idm: cardIdm, pmm: pmm, systemCodes: const [0x88B4]),
      );
      final events = <CardEmulationEvent>[];
      final cancel = Completer<void>();
      var targets = 0;

      final pn532 = _ScriptedPn532((command, payload) {
        switch (command) {
          case 0x8C:
            // A Type A reader activates ISO-DEP or 106k, then nobody else comes.
            if (++targets == 1) return [0x08, 0xE0, 0x80];
            if (targets == 2) return [0x00, 0x00]; // 106k non-ISO-DEP
            Timer(Duration.zero, cancel.complete);
            return null;
          case 0x02:
            return [0x32, 0x01, 0x06, 0x07];
          default:
            return [];
        }
      });

      await HinataCardEmulator(
        pn532.api,
      ).run(target, cancel: cancel.future, onEvent: events.add);

      expect(events, [CardEmulationEvent.waitingForReader]);
      expect(pn532.commands.where((c) => c == 0x86), isEmpty);
      // Non-NDEF FeliCa sets _defaultParameters (0x14) instead of _targetParameters (0x34).
      expect(pn532.requests[0].$1, 0x12);
      expect(pn532.requests[0].$2, [0x14]);
      final params = pn532.requests.firstWhere((r) => r.$1 == 0x8C).$2;
      // MifareParams is filled with zeroes so PN532 won't respond to Type A 106k.
      expect(params.sublist(0, 7), [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(params.sublist(7, 25), [...cardIdm, ...pmm, 0x88, 0xB4]);
    },
  );

  test(
    'a FeliCa card responds to both 212 kbps and 424 kbps FeliCa readers',
    () async {
      final cardIdm = Uint8List.fromList([0x01, 0x2E, 1, 2, 3, 4, 5, 6]);
      final pmm = Uint8List.fromList([0x00, 0xF1, 0, 0, 0, 0x01, 0x43, 0]);
      final target = EmulationTarget(
        kind: EmulationKind.felica,
        felica: FelicaTag(idm: cardIdm, pmm: pmm, systemCodes: const [0x88B4]),
      );
      final events = <CardEmulationEvent>[];
      final cancel = Completer<void>();
      var targets = 0;

      final pn532 = _ScriptedPn532((command, payload) {
        switch (command) {
          case 0x8C:
            // 1st: activated at 212 kbps (0x12)
            if (++targets == 1) return [0x12, 0x00];
            // 2nd: activated at 424 kbps (0x22)
            if (targets == 2) return [0x22, 0x00];
            Timer(Duration.zero, cancel.complete);
            return null;
          case 0x88:
            // initiator goes quiet immediately
            return null;
          case 0x02:
            return [0x32, 0x01, 0x06, 0x07];
          default:
            return [];
        }
      });

      await HinataCardEmulator(
        pn532.api,
      ).run(target, cancel: cancel.future, onEvent: events.add);

      expect(events, [
        CardEmulationEvent.waitingForReader,
        CardEmulationEvent.readerConnected,
        CardEmulationEvent.waitingForReader,
        CardEmulationEvent.readerConnected,
        CardEmulationEvent.waitingForReader,
      ]);
    },
  );

  test(
    'a FeliCa card with NDEF enables 106k Type A and responds to 106k, 212k, 424k',
    () async {
      final cardIdm = Uint8List.fromList([0x01, 0x2E, 1, 2, 3, 4, 5, 6]);
      final pmm = Uint8List.fromList([0x00, 0xF1, 0, 0, 0, 0x01, 0x43, 0]);
      final target = EmulationTarget(
        kind: EmulationKind.felica,
        felica: FelicaTag(idm: cardIdm, pmm: pmm, systemCodes: const [0x88B4]),
        type4: Type4NdefTag(message, maxRead: HinataCardEmulator.hidMaxRead),
      );
      final events = <CardEmulationEvent>[];
      final cancel = Completer<void>();
      var targets = 0;

      final pn532 = _ScriptedPn532((command, payload) {
        switch (command) {
          case 0x8C:
            // 1st: 106k ISO-DEP (Type 4)
            if (++targets == 1) return [0x08, 0xE0, 0x80];
            // 2nd: 212k FeliCa
            if (targets == 2) return [0x12, 0x00];
            // 3rd: 424k FeliCa
            if (targets == 3) return [0x22, 0x00];
            Timer(Duration.zero, cancel.complete);
            return null;
          case 0x86:
            // Type 4 reader disconnects
            return [0x29];
          case 0x88:
            // FeliCa reader goes quiet
            return null;
          case 0x02:
            return [0x32, 0x01, 0x06, 0x07];
          default:
            return [];
        }
      });

      await HinataCardEmulator(
        pn532.api,
      ).run(target, cancel: cancel.future, onEvent: events.add);

      // Sets _targetParameters (0x34) because it has NDEF
      expect(pn532.requests[0].$1, 0x12);
      expect(pn532.requests[0].$2, [0x34]);
      final params = pn532.requests.firstWhere((r) => r.$1 == 0x8C).$2;
      expect(params.sublist(0, 7), [0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x20]);

      expect(events, [
        CardEmulationEvent.waitingForReader,
        CardEmulationEvent.readerConnected,
        CardEmulationEvent.waitingForReader,
        CardEmulationEvent.readerConnected,
        CardEmulationEvent.waitingForReader,
        CardEmulationEvent.readerConnected,
        CardEmulationEvent.waitingForReader,
      ]);
    },
  );

  test('serves an Aime MIFARE Classic 1K card and restores registers', () async {
    final card = Aime(
      Uint8List.fromList([
        0x01, 0x23, 0x45, 0x67, 0x89, 0x01, 0x23, 0x45, 0x67, 0x89, //
      ]),
      physicalCard: Iso14443(
        Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
        0x08,
        0x0004,
      ),
    );
    final target = emulationTargetFor(
      card,
      type4MaxRead: HinataCardEmulator.hidMaxRead,
    );
    expect(target.kind, EmulationKind.mifareClassic);

    const uidInt = 0x08345678;
    late Crypto1 readerCrypto;
    final responses = <List<int>>[];
    final events = <CardEmulationEvent>[];
    final cancel = Completer<void>();
    var targets = 0;
    var step = 0;

    Uint8List encryptCmd(List<int> cmd) {
      final raw = [...cmd, ...crcA(cmd)];
      final enc = <int>[];
      final par = <int>[];
      for (final b in raw) {
        final ks = readerCrypto.byte();
        enc.add(b ^ ks);
        par.add(oddParity8(b) ^ readerCrypto.peek());
      }
      return packParity(enc, par).$1;
    }

    final pn532 = _ScriptedPn532((command, payload) {
      switch (command) {
        case 0x02:
          return [0x32, 0x01, 0x06, 0x07];
        case 0x08:
          return [];
        case 0x8C:
          if (++targets == 1) {
            // Activated at 106 kbps Type A with AUTH_B block 3 (CRC stripped).
            return [0x00, 0x61, 0x03];
          }
          Timer(Duration.zero, cancel.complete);
          return null;
        case 0x90:
          responses.add(payload);
          return [0x00];
        case 0x88:
          if (step == 0) {
            step = 1;
            final (ntBytes, _) = unpackParity(responses.last, 4);
            final nt =
                (ntBytes[0] << 24) |
                (ntBytes[1] << 16) |
                (ntBytes[2] << 8) |
                ntBytes[3];
            readerCrypto = Crypto1.fromBytes(aimeKey);
            readerCrypto.word(nt ^ uidInt);
            const nr = 0x11223344;
            final nrEnc = <int>[];
            final nrPar = <int>[];
            for (var i = 3; i >= 0; i--) {
              final b = (nr >> (8 * i)) & 0xFF;
              nrEnc.add(b ^ readerCrypto.byte(b));
              nrPar.add(oddParity8(b) ^ readerCrypto.peek());
            }
            final ar = prngSuccessor(nt, 64);
            final arEnc = <int>[];
            final arPar = <int>[];
            for (var i = 3; i >= 0; i--) {
              final b = (ar >> (8 * i)) & 0xFF;
              arEnc.add(b ^ readerCrypto.byte());
              arPar.add(oddParity8(b) ^ readerCrypto.peek());
            }
            return [
              0x00,
              ...packParity([...nrEnc, ...arEnc], [...nrPar, ...arPar]).$1,
            ];
          } else if (step == 1) {
            step = 2;
            // Absorb {at} in reader cipher state.
            for (var i = 0; i < 4; i++) {
              readerCrypto.byte();
            }
            return [
              0x00,
              ...encryptCmd(const [0x30, 0x02]),
            ];
          } else {
            // Absorb 18-byte encrypted READ response and send HALT.
            for (var i = 0; i < 18; i++) {
              readerCrypto.byte();
            }
            return [
              0x00,
              ...encryptCmd(const [0x50, 0x00]),
            ];
          }
        default:
          return [];
      }
    });

    await HinataCardEmulator(
      pn532.api,
    ).run(target, cancel: cancel.future, onEvent: events.add);

    expect(events, [
      CardEmulationEvent.waitingForReader,
      CardEmulationEvent.readerConnected,
      CardEmulationEvent.dataRead,
      CardEmulationEvent.waitingForReader,
    ]);
    expect(responses, hasLength(3));
    expect(pn532.requests.first.$1, 0x12);
    expect(pn532.requests.first.$2, [0x00]);
    expect(pn532.requests.where((r) => r.$1 == 0x08).first.$2, [
      0x63,
      0x01,
      0x3F,
    ]);
    final initPayload = pn532.requests.firstWhere((r) => r.$1 == 0x8C).$2;
    expect(initPayload.sublist(0, 7), [
      0x01,
      0x04,
      0x00,
      0x34,
      0x56,
      0x78,
      0x08,
    ]);

    // Restores CIU registers and SetParameters(0x14) on exit.
    final lastRequests = pn532.requests.sublist(pn532.requests.length - 3);
    expect(lastRequests[0].$1, 0x02);
    expect(lastRequests[1].$1, 0x08);
    expect(lastRequests[1].$2, [
      0x63, 0x01, 0x3B,
      0x63, 0x02, 0x80,
      0x63, 0x03, 0x80,
      0x63, 0x0D, 0x00,
      0x63, 0x3D, 0x00, //
    ]);
    expect(lastRequests[2].$1, 0x12);
    expect(lastRequests[2].$2, [0x14]);
  });
}
