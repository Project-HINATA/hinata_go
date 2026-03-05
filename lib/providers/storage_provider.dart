import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_instance.dart';
import '../models/saved_card.dart';

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
  static const String _kActiveInstanceIdKey = 'active_instance_id';

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
}
