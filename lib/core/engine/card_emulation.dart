import '../../models/card/aic.dart';
import '../../models/card/card.dart';
import '../../models/card/felica.dart';
import '../../models/card/ndef.dart';
import 'felica_dump_reader.dart';
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

/// A Lite-S reads every block through both of its services.
const _liteReadOnlyService = 0x000B;
const _liteReadWriteService = 0x0009;

/// The Lite-S blocks, which every Lite-S has whether or not they were saved.
final _liteFixedBlocks = FelicaDumpReader.liteBlocks.toSet();

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
/// were not all read. Those read as zeros.
bool emulationIsPartial(ICCard card) => card is Felica && !card.isFullyRead;

/// Whether [card] is a Lite or Lite-S, whose MAC answers to a reader's
/// challenge cannot be emulated.
bool emulatesLite(ICCard card) => card is Felica && card.isLite;

EmulationTarget emulationTargetFor(ICCard card, {required int type4MaxRead}) {
  switch (emulationKindOf(card)) {
    case EmulationKind.ndef:
      final message = (card as NdefCard).message;
      return EmulationTarget(
        kind: EmulationKind.ndef,
        type4: Type4NdefTag(message, maxRead: type4MaxRead),
        felica: Type3NdefTag(message, idm: Type3NdefTag.randomIdm()),
      );
    case final EmulationKind kind:
      final felica = card as Felica;
      final dump = felica.dump;
      final services = {...?dump?.services};
      // A Lite-S reads the same blocks through its read/write service.
      final liteBlocks = services[_liteReadOnlyService];
      if (felica.isLite && liteBlocks != null) {
        services.putIfAbsent(_liteReadWriteService, () => liteBlocks);
      }
      return EmulationTarget(
        kind: kind,
        felica: FelicaTag(
          idm: felica.id,
          pmm: felica.pmm,
          systemCodes: felica.systemCode,
          services: services,
          partial: !felica.isFullyRead,
          fixedBlocks: felica.isLite ? _liteFixedBlocks : const {},
          markerBlock: kind == EmulationKind.amusementIc
              ? Aic.spad0Block
              : null,
        ),
      );
    case null:
      throw ArgumentError.value(card.runtimeType, 'card', 'Cannot emulate');
  }
}
