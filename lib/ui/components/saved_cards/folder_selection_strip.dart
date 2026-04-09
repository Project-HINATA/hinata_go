import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../models/card_folder.dart';
import '../../ui_text.dart';

class FolderSelectionStrip extends ConsumerWidget {
  final List<CardFolder> folders;
  final String selectedFolderId;
  final ValueSetter<String> onFolderSelected;
  final Function(CardFolder folder) onFolderLongPress;

  const FolderSelectionStrip({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.onFolderSelected,
    required this.onFolderLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = folder.id == selectedFolderId;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onLongPress: () => onFolderLongPress(folder),
              child: FilterChip(
                label: Text(folderDisplayName(context, folder.id, folder.name)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    onFolderSelected(folder.id);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
