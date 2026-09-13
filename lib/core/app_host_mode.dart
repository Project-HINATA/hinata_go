import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AppHostMode { flutterShell, nativeIOS }

final appHostModeProvider = Provider<AppHostMode>(
  (_) => AppHostMode.flutterShell,
);
