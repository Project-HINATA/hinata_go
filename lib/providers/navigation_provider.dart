import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider to track the current active branch index in the main scaffold.
/// 0: Reader, 1: Cards, 2: Settings
final activeBranchProvider = NotifierProvider<ActiveBranchNotifier, int>(() {
  return ActiveBranchNotifier();
});

class ActiveBranchNotifier extends Notifier<int> {
  @override
  int build() {
    return 0;
  }

  void setIndex(int index) {
    state = index;
  }
}

/// Provider to track if the main scaffold is currently covered by a root-level route (like a dialog or CardDetail).
final isScaffoldCoveredProvider =
    NotifierProvider<ScaffoldCoveredNotifier, bool>(() {
      return ScaffoldCoveredNotifier();
    });

class ScaffoldCoveredNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setCovered(bool covered) {
    state = covered;
  }
}
