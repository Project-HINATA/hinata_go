import 'package:hinata_card_io/hinata_card_io.dart';

import '../../models/card/felica.dart';
import '../../models/card/iso14443a.dart';
import '../../models/card/iso15693.dart';

extension CardTagAdapter on CardTag {
  Object toAppCardTag() {
    final tag = this;
    return switch (tag) {
      FelicaTag() => Felica(tag.id, tag.pmm, tag.systemCode),
      Iso14443aTag() => Iso14443(tag.id, tag.sak, tag.atqa),
      Iso15693Tag() => Iso15693(tag.id),
      _ => tag,
    };
  }
}
