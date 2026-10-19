import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/card_folder.dart';
import '../../models/scanning_mode.dart';
import '../../providers/app_state_provider.dart';

/// One step through the app's pages.
enum AppSwipeMove { previous, next }

/// What a swipe should change. Null fields are left alone; a move can both
/// select a branch and restore the sub-page that belongs to it.
@immutable
class AppSwipeTarget {
  const AppSwipeTarget({this.branchIndex, this.mode, this.folderId});

  final int? branchIndex;
  final ScanningMode? mode;
  final String? folderId;

  bool get isEmpty => branchIndex == null && mode == null && folderId == null;

  @override
  bool operator ==(Object other) {
    return other is AppSwipeTarget &&
        other.branchIndex == branchIndex &&
        other.mode == mode &&
        other.folderId == folderId;
  }

  @override
  int get hashCode => Object.hash(branchIndex, mode, folderId);

  @override
  String toString() =>
      'AppSwipeTarget(branch: $branchIndex, mode: $mode, folder: $folderId)';
}

int _folderIndex(List<CardFolder> folders, String selectedFolderId) {
  final index = folders.indexWhere((folder) => folder.id == selectedFolderId);
  if (index != -1) return index;
  final favorites = folders.indexWhere(
    (folder) => folder.id == 'favorites_folder',
  );
  return favorites == -1 ? 0 : favorites;
}

String? _favoritesFolderId(List<CardFolder> folders) {
  if (folders.any((folder) => folder.id == 'favorites_folder')) {
    return 'favorites_folder';
  }
  return folders.isEmpty ? null : folders.first.id;
}

String? _lastFolderId(List<CardFolder> folders) {
  return folders.isEmpty ? null : folders.last.id;
}

/// The flat sequence used when the tab bar is horizontal:
/// scan Normal → scan Sender → cards folders → settings.
AppSwipeTarget resolveFullSequenceSwipe({
  required AppSwipeMove move,
  required int branchIndex,
  required ScanningMode mode,
  required List<CardFolder> folders,
  required String selectedFolderId,
}) {
  switch (branchIndex) {
    case 0:
      if (move == AppSwipeMove.next) {
        return mode == ScanningMode.normal
            ? const AppSwipeTarget(mode: ScanningMode.sender)
            : AppSwipeTarget(
                branchIndex: 1,
                folderId: _favoritesFolderId(folders),
              );
      }
      return mode == ScanningMode.sender
          ? const AppSwipeTarget(mode: ScanningMode.normal)
          : const AppSwipeTarget();

    case 1:
      final index = _folderIndex(folders, selectedFolderId);
      if (move == AppSwipeMove.next) {
        return index >= folders.length - 1
            ? const AppSwipeTarget(branchIndex: 2)
            : AppSwipeTarget(folderId: folders[index + 1].id);
      }
      return index <= 0
          ? const AppSwipeTarget(branchIndex: 0, mode: ScanningMode.sender)
          : AppSwipeTarget(folderId: folders[index - 1].id);

    case 2:
      return move == AppSwipeMove.previous
          ? AppSwipeTarget(branchIndex: 1, folderId: _lastFolderId(folders))
          : const AppSwipeTarget();

    default:
      return const AppSwipeTarget();
  }
}

/// Top-level tabs when the bar runs vertically.
AppSwipeTarget resolveBranchSwipe({
  required AppSwipeMove move,
  required int branchIndex,
}) {
  if (move == AppSwipeMove.next) {
    return branchIndex < 2
        ? AppSwipeTarget(branchIndex: branchIndex + 1)
        : const AppSwipeTarget();
  }
  return branchIndex > 0
      ? AppSwipeTarget(branchIndex: branchIndex - 1)
      : const AppSwipeTarget();
}

/// Sub-pages on the axis orthogonal to a vertical bar: scan modes and card
/// folders. At either end this stays inside the branch; the vertical gesture
/// owns top-level navigation.
AppSwipeTarget resolveSubPageSwipe({
  required AppSwipeMove move,
  required int branchIndex,
  required ScanningMode mode,
  required List<CardFolder> folders,
  required String selectedFolderId,
}) {
  switch (branchIndex) {
    case 0:
      if (move == AppSwipeMove.next) {
        return mode == ScanningMode.normal
            ? const AppSwipeTarget(mode: ScanningMode.sender)
            : const AppSwipeTarget();
      }
      return mode == ScanningMode.sender
          ? const AppSwipeTarget(mode: ScanningMode.normal)
          : const AppSwipeTarget();

    case 1:
      final index = _folderIndex(folders, selectedFolderId);
      if (move == AppSwipeMove.next) {
        return index < folders.length - 1
            ? AppSwipeTarget(folderId: folders[index + 1].id)
            : const AppSwipeTarget();
      }
      return index > 0
          ? AppSwipeTarget(folderId: folders[index - 1].id)
          : const AppSwipeTarget();

    default:
      return const AppSwipeTarget();
  }
}

/// Turns swipes into page changes using the app-wide navigation axis.
///
/// A horizontal bar walks the whole sequence horizontally. A vertical bar
/// leaves horizontal gestures for the current branch's sub-pages and uses
/// vertical gestures for the top-level tabs.
///
/// The detector sits above the pages and lets inner scrollables win their own
/// axis, so a list keeps scrolling instead of switching pages.
class AppSwipeNavigation extends ConsumerWidget {
  const AppSwipeNavigation({
    required this.tabAxis,
    required this.branchIndex,
    required this.onBranchSelected,
    required this.child,
    super.key,
  });

  final Axis tabAxis;
  final int branchIndex;
  final ValueChanged<int> onBranchSelected;
  final Widget child;

  static const double _minVelocity = 300;

  static AppSwipeMove? _moveFrom(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _minVelocity) return null;
    // Finger moves right/down: previous. Left/up: next.
    return velocity > 0 ? AppSwipeMove.previous : AppSwipeMove.next;
  }

  void _apply(WidgetRef ref, AppSwipeTarget target) {
    if (target.isEmpty) return;
    if (target.mode != null) {
      ref.read(scanningModeProvider.notifier).setMode(target.mode!);
    }
    if (target.folderId != null) {
      ref.read(selectedCardFolderIdProvider.notifier).select(target.folderId!);
    }
    final branch = target.branchIndex;
    if (branch != null && branch != branchIndex) {
      onBranchSelected(branch);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horizontalTabs = tabAxis == Axis.horizontal;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final move = _moveFrom(details);
        if (move == null) return;
        _apply(
          ref,
          horizontalTabs
              ? resolveFullSequenceSwipe(
                  move: move,
                  branchIndex: branchIndex,
                  mode: ref.read(scanningModeProvider),
                  folders: ref.read(cardFoldersProvider),
                  selectedFolderId: ref.read(selectedCardFolderIdProvider),
                )
              : resolveSubPageSwipe(
                  move: move,
                  branchIndex: branchIndex,
                  mode: ref.read(scanningModeProvider),
                  folders: ref.read(cardFoldersProvider),
                  selectedFolderId: ref.read(selectedCardFolderIdProvider),
                ),
        );
      },
      onVerticalDragEnd: horizontalTabs
          ? null
          : (details) {
              final move = _moveFrom(details);
              if (move == null) return;
              _apply(
                ref,
                resolveBranchSwipe(move: move, branchIndex: branchIndex),
              );
            },
      child: child,
    );
  }
}
