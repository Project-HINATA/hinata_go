import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/models/card_folder.dart';
import 'package:hinata_go/models/scanning_mode.dart';
import 'package:hinata_go/ui/widgets/app_swipe_navigation.dart';

List<CardFolder> _folders() => [
  CardFolder(id: 'history_folder', name: 'History'),
  CardFolder(id: 'favorites_folder', name: 'Favorites'),
  CardFolder(id: 'work', name: 'Work'),
  CardFolder(id: 'travel', name: 'Travel'),
];

void main() {
  group('full sequence on a horizontal bar', () {
    AppSwipeTarget resolve(
      AppSwipeMove move, {
      required int branch,
      ScanningMode mode = ScanningMode.normal,
      String folder = 'favorites_folder',
    }) {
      return resolveFullSequenceSwipe(
        move: move,
        branchIndex: branch,
        mode: mode,
        folders: _folders(),
        selectedFolderId: folder,
      );
    }

    test('walks Normal -> Sender -> Cards favorites', () {
      expect(
        resolve(AppSwipeMove.next, branch: 0),
        const AppSwipeTarget(mode: ScanningMode.sender),
      );
      expect(
        resolve(AppSwipeMove.next, branch: 0, mode: ScanningMode.sender),
        const AppSwipeTarget(branchIndex: 1, folderId: 'favorites_folder'),
      );
    });

    test('walks folders in strip order and ends at Settings', () {
      expect(
        resolve(AppSwipeMove.next, branch: 1),
        const AppSwipeTarget(folderId: 'work'),
      );
      expect(
        resolve(AppSwipeMove.next, branch: 1, folder: 'travel'),
        const AppSwipeTarget(branchIndex: 2),
      );
    });

    test('walks back through folders into Sender', () {
      expect(
        resolve(AppSwipeMove.previous, branch: 2),
        const AppSwipeTarget(branchIndex: 1, folderId: 'travel'),
      );
      expect(
        resolve(AppSwipeMove.previous, branch: 1),
        const AppSwipeTarget(folderId: 'history_folder'),
      );
      expect(
        resolve(AppSwipeMove.previous, branch: 1, folder: 'history_folder'),
        const AppSwipeTarget(branchIndex: 0, mode: ScanningMode.sender),
      );
      expect(
        resolve(AppSwipeMove.previous, branch: 0, mode: ScanningMode.sender),
        const AppSwipeTarget(mode: ScanningMode.normal),
      );
    });

    test('stops at both ends', () {
      expect(resolve(AppSwipeMove.previous, branch: 0), const AppSwipeTarget());
      expect(resolve(AppSwipeMove.next, branch: 2), const AppSwipeTarget());
    });
  });

  group('vertical bar', () {
    test('moves top-level branches only', () {
      expect(
        resolveBranchSwipe(move: AppSwipeMove.next, branchIndex: 0),
        const AppSwipeTarget(branchIndex: 1),
      );
      expect(
        resolveBranchSwipe(move: AppSwipeMove.next, branchIndex: 2),
        const AppSwipeTarget(),
      );
      expect(
        resolveBranchSwipe(move: AppSwipeMove.previous, branchIndex: 0),
        const AppSwipeTarget(),
      );
    });

    test('moves modes inside Scan', () {
      AppSwipeTarget resolve(AppSwipeMove move, ScanningMode mode) {
        return resolveSubPageSwipe(
          move: move,
          branchIndex: 0,
          mode: mode,
          folders: _folders(),
          selectedFolderId: 'favorites_folder',
        );
      }

      expect(
        resolve(AppSwipeMove.next, ScanningMode.normal),
        const AppSwipeTarget(mode: ScanningMode.sender),
      );
      expect(
        resolve(AppSwipeMove.next, ScanningMode.sender),
        const AppSwipeTarget(),
      );
      expect(
        resolve(AppSwipeMove.previous, ScanningMode.sender),
        const AppSwipeTarget(mode: ScanningMode.normal),
      );
    });

    test('moves folders inside Cards and stops at the ends', () {
      AppSwipeTarget resolve(AppSwipeMove move, String folder) {
        return resolveSubPageSwipe(
          move: move,
          branchIndex: 1,
          mode: ScanningMode.normal,
          folders: _folders(),
          selectedFolderId: folder,
        );
      }

      expect(
        resolve(AppSwipeMove.next, 'favorites_folder'),
        const AppSwipeTarget(folderId: 'work'),
      );
      expect(
        resolve(AppSwipeMove.previous, 'favorites_folder'),
        const AppSwipeTarget(folderId: 'history_folder'),
      );
      expect(
        resolve(AppSwipeMove.previous, 'history_folder'),
        const AppSwipeTarget(),
      );
      expect(resolve(AppSwipeMove.next, 'travel'), const AppSwipeTarget());
    });
  });
}
