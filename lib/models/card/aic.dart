import 'dart:typed_data';

import '../../core/crypto/spad0.dart';
import 'card.dart';
import 'felica.dart';
import 'felica_dump.dart';

/// An Amusement IC: a FeliCa Lite-S whose S_PAD0 holds the access code.
class Aic extends Felica implements HasAccessCode {
  /// The Lite-S service that reads every block.
  static const service = 0x000B;
  static const spad0Block = 0;

  /// The access code, read from S_PAD0 in [dump].
  late final Uint8List accessCode = accessCodeOf(
    dump?.block(service, spad0Block),
  );

  Aic(
    super.id,
    super.pmm,
    super.systemCode, {
    required FelicaDump super.dump,
    super.tags,
  });

  /// A card known only by its access code, as entered by hand or saved before
  /// cards kept their blocks. Only S_PAD0 is known, and of it only the access
  /// code and the zero before it; the bytes ahead of them are left zero.
  factory Aic.fromAccessCode(
    Uint8List id,
    Uint8List pmm,
    Uint16List systemCode,
    Uint8List accessCode, {
    List<CardTag> tags = const [],
  }) {
    return Aic(
      id,
      pmm,
      systemCode,
      dump: FelicaDump(
        complete: false,
        services: {
          if (accessCode.length == 10)
            service: {spad0Block: spad0For(accessCode)},
        },
      ),
      tags: tags,
    );
  }

  /// S_PAD0 holding [accessCode], with zeros ahead of it.
  static Uint8List spad0For(Uint8List accessCode) {
    if (accessCode.length != 10) {
      throw ArgumentError.value(accessCode.length, 'accessCode.length');
    }
    return spad0Encrypt(Uint8List(16)..setAll(6, accessCode));
  }

  /// The access code in [spad0], or an empty list without one.
  static Uint8List accessCodeOf(Uint8List? spad0) {
    if (spad0 == null || spad0.length != 16) return Uint8List(0);
    return Uint8List.fromList(spad0Decrypt(spad0).sublist(6, 16));
  }

  /// Whether [spad0] holds an Amusement IC access code: the byte before it is
  /// zero and it starts with 5.
  static bool holdsAccessCode(Uint8List spad0) {
    if (spad0.length != 16 || spad0.every((byte) => byte == 0)) return false;
    final plain = spad0Decrypt(spad0);
    return plain[5] == 0 && plain[6] & 0xF0 == 0x50;
  }

  @override
  String get accessCodeString =>
      accessCode.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  String get manufacturer {
    if (accessCodeString.length < 2) return 'Unknown';
    final prefix = accessCodeString.substring(0, 2);

    return switch (prefix) {
      '50' => 'SEGA',
      '51' => 'Bandai Namco',
      '52' => 'KONAMI',
      '53' => 'Taito',
      _ => 'Unknown',
    };
  }

  @override
  String get showedValue => accessCodeString.toUpperCase();

  @override
  String get name => "Amusement IC";

  @override
  String? get logoPath => "assets/cardlogo/aic.svg";

  @override
  String? get type => "aic";

  @override
  String? get gamePayload => "$idString:$accessCodeString";

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'accessCode': accessCodeString};
  }

  factory Aic.fromJson(Map<String, dynamic> json) {
    final felica = Felica.fromJson(json);
    final dump = felica.dump;
    if (dump != null && dump.block(service, spad0Block) != null) {
      return Aic(
        felica.id,
        felica.pmm,
        felica.systemCode,
        dump: dump,
        tags: felica.tags,
      );
    }
    return Aic.fromAccessCode(
      felica.id,
      felica.pmm,
      felica.systemCode,
      ICCard.hexToBytes(json['accessCode'] as String? ?? ''),
      tags: felica.tags,
    );
  }
}
