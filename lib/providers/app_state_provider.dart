import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_provider.dart';
import '../models/remote_instance.dart';
import '../models/saved_card.dart';

final instancesProvider =
    NotifierProvider<InstancesNotifier, List<RemoteInstance>>(() {
      return InstancesNotifier();
    });

class InstancesNotifier extends Notifier<List<RemoteInstance>> {
  @override
  List<RemoteInstance> build() {
    return ref.watch(storageProvider).getInstances();
  }

  void addInstance(RemoteInstance instance) {
    state = [...state, instance];
    ref.read(storageProvider).saveInstances(state);
  }

  void updateInstance(RemoteInstance updated) {
    state = state.map((e) => e.id == updated.id ? updated : e).toList();
    ref.read(storageProvider).saveInstances(state);
  }

  void removeInstance(String id) {
    state = state.where((e) => e.id != id).toList();
    ref.read(storageProvider).saveInstances(state);
  }
}

final activeInstanceIdProvider =
    NotifierProvider<ActiveInstanceIdNotifier, String?>(() {
      return ActiveInstanceIdNotifier();
    });

class ActiveInstanceIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    return ref.watch(storageProvider).getActiveInstanceId();
  }

  void setActiveId(String? id) {
    state = id;
    ref.read(storageProvider).setActiveInstanceId(id);
  }
}

final activeInstanceProvider = Provider<RemoteInstance?>((ref) {
  final instances = ref.watch(instancesProvider);
  final activeId = ref.watch(activeInstanceIdProvider);
  if (activeId == null) return null;

  try {
    return instances.firstWhere((e) => e.id == activeId);
  } catch (_) {
    return null;
  }
});

// Saved Cards
final savedCardsProvider =
    NotifierProvider<SavedCardsNotifier, List<SavedCard>>(() {
      return SavedCardsNotifier();
    });

class SavedCardsNotifier extends Notifier<List<SavedCard>> {
  @override
  List<SavedCard> build() {
    return ref.watch(storageProvider).getSavedCards();
  }

  void addCard(SavedCard card) {
    state = [...state, card];
    ref.read(storageProvider).saveSavedCards(state);
  }

  void updateCard(SavedCard updated) {
    state = state.map((e) => e.id == updated.id ? updated : e).toList();
    ref.read(storageProvider).saveSavedCards(state);
  }

  void removeCard(String id) {
    state = state.where((e) => e.id != id).toList();
    ref.read(storageProvider).saveSavedCards(state);
  }
}
