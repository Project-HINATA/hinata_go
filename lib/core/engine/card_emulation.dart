import '../../models/card/aic.dart';
import '../../models/card/card.dart';
import '../../models/card/felica.dart';
import '../../models/card/ndef.dart';
import 'felica_tag.dart';
import 'type3_ndef_tag.dart';
import 'type4_ndef_tag.dart';

enum EmulationKind { ndef, felica, amusementIc }

/// What a reader finds when it polls the emulating PN532.
class EmulationTarget {
  final EmulationKind kind;

  /// Answers Type A readers through ISO-DEP; without it they get nothing.
  /// An NDEF card has one, and so does a FeliCa card holding NDEF.
  final Type4NdefTag? type4;
  final FelicaTag felica;

  const EmulationTarget({required this.kind, required this.felica, this.type4});
}

/// A Lite-S reads every block through both of its services.
const _liteReadOnlyService = 0x000B;
const _liteReadWriteService = 0x0009;

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

/// Whether emulating [card] leaves out blocks the card had, because they
/// were not all read. A reader finds them missing.
bool emulationIsPartial(ICCard card) => card is Felica && !card.isFullyRead;

/// Whether [card] is a Lite or Lite-S, whose MAC answers to a reader's
/// challenge cannot be emulated.
bool emulatesLite(ICCard card) => card is Felica && card.isLite;

/// [felicaMaxBlocks] bounds the blocks one FeliCa read answers, as the
/// reader can pass them.
EmulationTarget emulationTargetFor(
  ICCard card, {
  required int type4MaxRead,
  int felicaMaxBlocks = FelicaTag.defaultMaxBlocksPerRead,
}) {
  switch (emulationKindOf(card)) {
    case EmulationKind.ndef:
      final message = (card as NdefCard).message;
      return EmulationTarget(
        kind: EmulationKind.ndef,
        type4: Type4NdefTag(message, maxRead: type4MaxRead),
        felica: Type3NdefTag(
          message,
          idm: Type3NdefTag.randomIdm(),
          maxBlocksPerRead: felicaMaxBlocks,
        ),
      );
    case final EmulationKind kind:
      final felica = card as Felica;
      // Each system's services, in the order of the card's system codes.
      final systems = [
        for (final code in felica.systemCode)
          {
            ...?felica.dump?.systems
                .where((system) => system.code == code)
                .firstOrNull
                ?.services,
          },
      ];
      // A Lite-S reads the same blocks through its read/write service.
      final liteBlocks = systems.first[_liteReadOnlyService];
      if (felica.isLite && liteBlocks != null) {
        systems.first.putIfAbsent(_liteReadWriteService, () => liteBlocks);
      }
      final message = ndefOf(felica)?.message;
      return EmulationTarget(
        kind: kind,
        type4: message != null && message.length <= Type4NdefTag.maxMessageSize
            ? Type4NdefTag(message, maxRead: type4MaxRead)
            : null,
        felica: FelicaTag(
          idm: Felica.systemIdm(felica.id, 0),
          pmm: felica.pmm,
          systemCodes: felica.systemCode,
          // A Lite-S holding NDEF answers as a Type 3 tag too.
          aliasCodes: felica.isLite && message != null
              ? const [Felica.ndefSystemCode]
              : const [],
          services: systems.first,
          otherSystems: systems.skip(1).toList(),
          markerBlock: kind == EmulationKind.amusementIc
              ? Aic.spad0Block
              : null,
          maxBlocksPerRead: felicaMaxBlocks,
        ),
      );
    case null:
      throw ArgumentError.value(card.runtimeType, 'card', 'Cannot emulate');
  }
}
