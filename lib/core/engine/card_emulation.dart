import 'dart:typed_data';

import '../../models/card/aic.dart';
import '../../models/card/card.dart';
import '../../models/card/felica.dart';
import '../../models/card/ndef.dart';
import '../crypto/spad0.dart';
import 'felica_tag.dart';
import 'type3_ndef_tag.dart';
import 'type4_ndef_tag.dart';

enum EmulationKind { ndef, felica, amusementIc }

/// What a reader finds when it polls the emulating PN532.
class EmulationTarget {
  final EmulationKind kind;

  /// Answers Type A readers through ISO-DEP; without it they get nothing.
  final Type4NdefTag? type4;
  final FelicaTag felica;

  const EmulationTarget({required this.kind, required this.felica, this.type4});
}

/// Amusement IC is a FeliCa Lite-S; S_PAD0 holds the access code.
const _liteSReadOnlyService = 0x000B;
const _liteSReadWriteService = 0x0009;

/// The kind [card] would be emulated as, or null when it cannot be.
///
/// Only data saved with the card is emulated, never data that needs
/// authentication to read.
EmulationKind? emulationKindOf(ICCard card) {
  if (card is NdefCard) {
    final length = card.message.length;
    return length > 0 && length <= Type4NdefTag.maxMessageSize
        ? EmulationKind.ndef
        : null;
  }
  if (card is! Felica ||
      card.id.length != 8 ||
      card.pmm.length != 8 ||
      card.systemCode.isEmpty) {
    return null;
  }
  if (card is Aic) {
    return card.accessCode.length == 10 ? EmulationKind.amusementIc : null;
  }
  return EmulationKind.felica;
}

EmulationTarget emulationTargetFor(ICCard card, {required int type4MaxRead}) {
  switch (emulationKindOf(card)) {
    case EmulationKind.ndef:
      final message = (card as NdefCard).message;
      return EmulationTarget(
        kind: EmulationKind.ndef,
        type4: Type4NdefTag(message, maxRead: type4MaxRead),
        felica: Type3NdefTag(message, idm: Type3NdefTag.randomIdm()),
      );
    case EmulationKind.amusementIc:
      final aic = card as Aic;
      return EmulationTarget(
        kind: EmulationKind.amusementIc,
        felica: FelicaTag(
          idm: aic.id,
          pmm: aic.pmm,
          systemCodes: aic.systemCode,
          services: const {_liteSReadOnlyService, _liteSReadWriteService},
          blocks: {0: amusementIcSpad0(aic.accessCode)},
          markerBlock: 0,
        ),
      );
    case EmulationKind.felica:
      final felica = card as Felica;
      return EmulationTarget(
        kind: EmulationKind.felica,
        felica: FelicaTag(
          idm: felica.id,
          pmm: felica.pmm,
          systemCodes: felica.systemCode,
        ),
      );
    case null:
      throw ArgumentError.value(card.runtimeType, 'card', 'Cannot emulate');
  }
}

/// S_PAD0 of an Amusement IC holding [accessCode]. Only the access code and
/// the zero before it are known from a read card; the bytes ahead of them
/// are left zero.
Uint8List amusementIcSpad0(Uint8List accessCode) {
  if (accessCode.length != 10) {
    throw ArgumentError.value(accessCode.length, 'accessCode.length');
  }
  return spad0Encrypt(Uint8List(16)..setAll(6, accessCode));
}
