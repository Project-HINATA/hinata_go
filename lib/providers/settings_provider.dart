import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_provider.dart';

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class AppSettings {
  final bool enableSecondaryConfirmation;

  AppSettings({required this.enableSecondaryConfirmation});

  AppSettings copyWith({bool? enableSecondaryConfirmation}) {
    return AppSettings(
      enableSecondaryConfirmation:
          enableSecondaryConfirmation ?? this.enableSecondaryConfirmation,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.watch(storageProvider).getSettings();
  }

  void updateEnableSecondaryConfirmation(bool value) {
    state = state.copyWith(enableSecondaryConfirmation: value);
    ref.read(storageProvider).saveSettings(state);
  }
}
