import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hinata_go/l10n/app_localizations.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);

  TextTheme get textTheme => theme.textTheme;

  ColorScheme get colorScheme => theme.colorScheme;

  MediaQueryData get mediaQuery => MediaQuery.of(this);

  NavigatorState get navigator => Navigator.of(this);

  NavigatorState get rootNavigator => Navigator.of(this, rootNavigator: true);

  ModalRoute<dynamic>? get modalRoute => ModalRoute.of(this);

  ui.FlutterView get flutterView => View.of(this);

  AppLocalizations get l10n => AppLocalizations.of(this);
}
