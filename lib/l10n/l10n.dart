import 'dart:ui';
import 'app_localizations.dart';

export 'app_localizations.dart';
export 'package:hinata_go/context_extensions.dart' show BuildContextX;

/// Global context-free accessor for localized strings.
AppLocalizations get l10n => L10nHolder.current;

class L10nHolder {
  static AppLocalizations current = _init();

  static AppLocalizations _init() {
    try {
      return lookupAppLocalizations(PlatformDispatcher.instance.locale);
    } catch (_) {
      return lookupAppLocalizations(const Locale('zh'));
    }
  }

  static void update(AppLocalizations newL10n) {
    current = newL10n;
  }
}
