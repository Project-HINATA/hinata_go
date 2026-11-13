import 'dart:typed_data';

import '../../models/card/aic.dart';
import '../../models/card/aime.dart';
import '../../models/card/banapass.dart';
import '../../models/card/card.dart';
import '../../models/card/felica.dart';
import '../../models/card/ndef.dart';
import 'felica_tag.dart';
import 'mifare_classic_tag.dart';
import 'mifare_write_payload.dart';
import 'type3_ndef_tag.dart';
import 'type4_ndef_tag.dart';

enum EmulationKind { ndef, felica, amusementIc, mifareClassic }

/// What a reader finds when it polls the emulating PN532.
class EmulationTarget {
  final EmulationKind kind;

  /// Answers Type A readers through ISO-DEP; without it they get nothing.
  /// An NDEF card has one, and so does a FeliCa card holding NDEF.
  final Type4NdefTag? type4;
  final FelicaTag? felica;
  final MifareClassicTag? mifare;

  const EmulationTarget({
    required this.kind,
    this.felica,
    this.type4,
    this.mifare,
  }) : assert((felica != null) != (mifare != null));
}

/// A Lite-S reads every block through both of its services.
const _liteReadOnlyService = 0x000B;
const _liteReadWriteService = 0x0009;

final _defaultMifareTrailer = Uint8List.fromList(const [
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
  0xFF, 0x07, 0x80, 0x69,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
]);

/// The kind [card] would be emulated as, or null when it cannot be.
EmulationKind? emulationKindOf(ICCard card) {
  if (card is NdefCard) {
    final length = card.message.length;
    return length > 0 && length <= Type4NdefTag.maxMessageSize
        ? EmulationKind.ndef
        : null;
  }
  if (card is Aime || card is Banapass) {
    return MifareCardWritePayload.canBuild(card)
        ? EmulationKind.mifareClassic
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
    case EmulationKind.mifareClassic:
      final payload = MifareCardWritePayload.fromCard(
        card,
        CardWriteMode.rewritable,
      );
      final uid = _mifareUidFor(card, payload);
      final bcc = uid[0] ^ uid[1] ^ uid[2] ^ uid[3];
      final block0 = Uint8List(16)
        ..setAll(0, [uid[0], uid[1], uid[2], uid[3], bcc, 0x08, 0x04, 0x00]);
      final blocks = List<Uint8List>.generate(64, (index) {
        if (index == 0) return block0;
        if (index == 3) return payload.trailer;
        if (index < 3) return payload.dataBlocks[index] ?? Uint8List(16);
        if (index & 3 == 3) return Uint8List.fromList(_defaultMifareTrailer);
        return Uint8List(16);
      });
      return EmulationTarget(
        kind: EmulationKind.mifareClassic,
        mifare: MifareClassicTag(
          uid: uid,
          blocks: blocks,
          markerBlock: card is Aime ? 2 : 1,
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

Uint8List _mifareUidFor(ICCard card, MifareCardWritePayload payload) {
  if (card.id.length >= 4) {
    final tail = card.id.sublist(card.id.length - 3);
    if (tail.any((b) => b != 0)) {
      return Uint8List.fromList([0x08, ...tail]);
    }
  }
  final block = payload.dataBlocks[2] ?? payload.dataBlocks[1];
  if (block != null) {
    final tail = block.sublist(13, 16);
    if (tail.any((b) => b != 0)) {
      return Uint8List.fromList([0x08, ...tail]);
    }
  }
  return Uint8List.fromList(const [0x08, 0x12, 0x34, 0x56]);
}
