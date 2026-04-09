import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'storage_provider.dart';
import '../models/remote_instance.dart';
import '../models/card/saved_card.dart';
import '../models/card_folder.dart';
import '../models/scan_log.dart';
import '../models/scanning_mode.dart';

// --- Scanning Mode ---
final scanningModeProvider =
    NotifierProvider<ScanningModeNotifier, ScanningMode>(() {
      return ScanningModeNotifier();
    });

class ScanningModeNotifier extends Notifier<ScanningMode> {
  @override
  ScanningMode build() {
    return ref.watch(storageProvider).getScanningMode();
  }

  void setMode(ScanningMode mode) {
    state = mode;
    ref.read(storageProvider).saveScanningMode(mode);
  }
}

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

// --- Saved Cards ---
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
    // Deduplication check: Do not add if a card with same value exists in this folder
    final exists = state.any(
      (c) => c.card.value == card.card.value && c.folderId == card.folderId,
    );
    if (!exists) {
      state = [...state, card];
      ref.read(storageProvider).saveSavedCards(state);
    }
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

// --- Card Folders ---
final cardFoldersProvider =
    NotifierProvider<CardFoldersNotifier, List<CardFolder>>(() {
      return CardFoldersNotifier();
    });

class CardFoldersNotifier extends Notifier<List<CardFolder>> {
  @override
  List<CardFolder> build() {
    final storedFolders = ref.watch(storageProvider).getCardFolders();

    // Ensure default folders exist
    bool hasHistory = storedFolders.any((f) => f.id == 'history_folder');
    bool hasFavorites = storedFolders.any((f) => f.id == 'favorites_folder');

    List<CardFolder> initialFolders = List.from(storedFolders);

    if (!hasHistory) {
      initialFolders.insert(
        0,
        CardFolder(id: 'history_folder', name: 'History'),
      );
    }
    if (!hasFavorites) {
      initialFolders.insert(
        hasHistory ? 1 : 0,
        CardFolder(id: 'favorites_folder', name: 'Favorites'),
      );
    }

    if (!hasHistory || !hasFavorites) {
      Future.microtask(
        () => ref.read(storageProvider).saveCardFolders(initialFolders),
      );
    }

    return initialFolders;
  }

  void addFolder(CardFolder folder) {
    state = [...state, folder];
    ref.read(storageProvider).saveCardFolders(state);
  }

  void updateFolder(CardFolder updated) {
    state = state.map((e) => e.id == updated.id ? updated : e).toList();
    ref.read(storageProvider).saveCardFolders(state);
  }

  void reorderFolders(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = state.removeAt(oldIndex);
    state.insert(newIndex, item);
    // Trigger state update
    state = [...state];
    ref.read(storageProvider).saveCardFolders(state);
  }

  void removeFolder(String id) {
    if (id == 'history_folder' || id == 'favorites_folder') {
      return; // Cannot delete builtin folders
    }
    state = state.where((e) => e.id != id).toList();
    ref.read(storageProvider).saveCardFolders(state);

    // Also remove all cards in this folder
    final cards = ref.read(savedCardsProvider);
    final cardsToRemove = cards
        .where((c) => c.folderId == id)
        .map((c) => c.id)
        .toList();
    for (final cardId in cardsToRemove) {
      ref.read(savedCardsProvider.notifier).removeCard(cardId);
    }
  }
}

// --- Scan Logs ---
final scanLogsProvider = NotifierProvider<ScanLogsNotifier, List<ScanLog>>(() {
  return ScanLogsNotifier();
});

class ScanLogsNotifier extends Notifier<List<ScanLog>> {
  @override
  List<ScanLog> build() {
    return ref.watch(storageProvider).getScanLogs();
  }

  void addLog(ScanLog log) {
    state = [...state, log];
    ref.read(storageProvider).saveScanLogs(state);
  }

  void clearLogs() {
    state = [];
    ref.read(storageProvider).saveScanLogs(state);
  }
}
