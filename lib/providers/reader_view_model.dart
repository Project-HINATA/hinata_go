import 'package:hooks_riverpod/hooks_riverpod.dart';

class ReaderViewState {
  // Keeping this for now if needed for other UI states, or we can make it empty
  ReaderViewState();
}

final readerViewModelProvider =
    NotifierProvider<ReaderViewModel, ReaderViewState>(() {
      return ReaderViewModel();
    });

class ReaderViewModel extends Notifier<ReaderViewState> {
  @override
  ReaderViewState build() {
    return ReaderViewState();
  }
}
