import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/services/reader/hinata_ndef_emulator.dart';
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

void main() {
  final message = Uint8List.fromList([
    0xD1, 0x01, 0x04, 0x55, 0x04, 0x61, 0x2E, 0x62, //
  ]);

  test('serves the message to a phone, then waits for the next one', () async {
    final apdus = Queue<List<int>>.of([
      [0x00, 0xA4, 0x04, 0x00, 0x07, 0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01],
      [0x00, 0xA4, 0x00, 0x0C, 0x02, 0xE1, 0x04],
      [0x00, 0xB0, 0x00, 0x00, 0x02],
      [0x00, 0xB0, 0x00, 0x02, 0x08],
    ]);
    final responses = <List<int>>[];
    final events = <NdefEmulationEvent>[];
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

    await HinataNdefEmulator(
      pn532.api,
    ).run(message, cancel: cancel.future, onEvent: events.add, idm: idm);

    expect(events, [
      NdefEmulationEvent.waitingForPhone,
      NdefEmulationEvent.phoneConnected,
      NdefEmulationEvent.messageRead,
      NdefEmulationEvent.waitingForPhone,
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
    final events = <NdefEmulationEvent>[];
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

    await HinataNdefEmulator(
      pn532.api,
    ).run(message, cancel: cancel.future, onEvent: events.add, idm: idm);

    expect(events, [
      NdefEmulationEvent.waitingForPhone,
      NdefEmulationEvent.phoneConnected,
      NdefEmulationEvent.messageRead,
      NdefEmulationEvent.waitingForPhone,
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
        const Duration(milliseconds: HinataNdefEmulator.felicaIdleTimeoutMs),
      ),
    );
    expect(pn532.requests.last.$2, [0x14]);
  });
}
