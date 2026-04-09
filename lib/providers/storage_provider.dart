import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_instance.dart';
import '../models/card/saved_card.dart';
import '../models/card_folder.dart';
import '../models/scan_log.dart';
import 'settings_provider.dart';
import '../models/scanning_mode.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final storageProvider = Provider<StorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StorageService(prefs);
});

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static const String _kInstancesKey = 'instances';
  static const String _kSavedCardsKey = 'saved_cards';
  static const String _kCardFoldersKey = 'card_folders';
  static const String _kScanLogsKey = 'scan_logs';
  static const String _kActiveInstanceIdKey = 'active_instance_id';
  static const String _kCardExpirationSecondsKey = 'card_expiration_seconds';
  static const String _kAppLanguageKey = 'app_language';
  static const String _kScanningModeKey = 'scanning_mode';

  // --- Instances ---

  List<RemoteInstance> getInstances() {
    final String? jsonString = _prefs.getString(_kInstancesKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((e) => RemoteInstance.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveInstances(List<RemoteInstance> instances) async {
    final String jsonString = jsonEncode(
      instances.map((e) => e.toJson()).toList(),
    );
    await _prefs.setString(_kInstancesKey, jsonString);
  }

  String? getActiveInstanceId() {
    return _prefs.getString(_kActiveInstanceIdKey);
  }

  Future<void> setActiveInstanceId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveInstanceIdKey);
    } else {
      await _prefs.setString(_kActiveInstanceIdKey, id);
    }
  }

  // --- Saved Cards ---
  List<SavedCard> getSavedCards() {
    final String? jsonString = _prefs.getString(_kSavedCardsKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSavedCards(List<SavedCard> cards) async {
    final String jsonString = jsonEncode(cards.map((e) => e.toJson()).toList());
    await _prefs.setString(_kSavedCardsKey, jsonString);
  }

  // --- Card Folders ---
  List<CardFolder> getCardFolders() {
    final String? jsonString = _prefs.getString(_kCardFoldersKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((e) => CardFolder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveCardFolders(List<CardFolder> folders) async {
    final String jsonString = jsonEncode(
      folders.map((e) => e.toJson()).toList(),
    );
    await _prefs.setString(_kCardFoldersKey, jsonString);
  }

  // --- Scan Logs ---
  List<ScanLog> getScanLogs() {
    final String? jsonString = _prefs.getString(_kScanLogsKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((e) => ScanLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveScanLogs(List<ScanLog> logs) async {
    final String jsonString = jsonEncode(logs.map((e) => e.toJson()).toList());
    await _prefs.setString(_kScanLogsKey, jsonString);
  }

  // --- Settings ---
  AppSettings getSettings() {
    final cardExpirationSeconds =
        _prefs.getInt(_kCardExpirationSecondsKey) ?? 15;

    return AppSettings(
      cardExpirationSeconds: cardExpirationSeconds,
      language: AppLanguageX.fromStorageValue(
        _prefs.getString(_kAppLanguageKey),
      ),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setInt(
      _kCardExpirationSecondsKey,
      settings.cardExpirationSeconds,
    );
    await _prefs.setString(_kAppLanguageKey, settings.language.storageValue);
  }

  // --- Scanning Mode ---
  ScanningMode getScanningMode() {
    final String? modeStr = _prefs.getString(_kScanningModeKey);
    if (modeStr == 'sender') return ScanningMode.sender;
    return ScanningMode.normal;
  }

  Future<void> saveScanningMode(ScanningMode mode) async {
    await _prefs.setString(_kScanningModeKey, mode.name);
  }
}
