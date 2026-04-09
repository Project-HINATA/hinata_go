import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import 'storage_provider.dart';

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class AppSettings {
  final int cardExpirationSeconds;
  final AppLanguage language;

  AppSettings({required this.cardExpirationSeconds, required this.language});

  AppSettings copyWith({int? cardExpirationSeconds, AppLanguage? language}) {
    return AppSettings(
      cardExpirationSeconds:
          cardExpirationSeconds ?? this.cardExpirationSeconds,
      language: language ?? this.language,
    );
  }
}

enum AppLanguage { system, english, simplifiedChinese }

extension AppLanguageX on AppLanguage {
  Locale? get locale {
    switch (this) {
      case AppLanguage.system:
        return null;
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.simplifiedChinese:
        return const Locale('zh');
    }
  }

  String get storageValue {
    switch (this) {
      case AppLanguage.system:
        return 'system';
      case AppLanguage.english:
        return 'en';
      case AppLanguage.simplifiedChinese:
        return 'zh';
    }
  }

  static AppLanguage fromStorageValue(String? value) {
    switch (value) {
      case 'en':
        return AppLanguage.english;
      case 'zh':
        return AppLanguage.simplifiedChinese;
      case 'system':
      default:
        return AppLanguage.system;
    }
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.watch(storageProvider).getSettings();
  }

  void updateCardExpirationSeconds(int value) {
    state = state.copyWith(cardExpirationSeconds: value);
    ref.read(storageProvider).saveSettings(state);
  }

  void updateLanguage(AppLanguage language) {
    state = state.copyWith(language: language);
    ref.read(storageProvider).saveSettings(state);
  }
}
