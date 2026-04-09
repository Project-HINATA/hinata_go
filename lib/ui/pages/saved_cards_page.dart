import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/card/saved_card.dart';
import '../../models/card_folder.dart';
import '../../models/remote_instance.dart';
import '../../models/scan_log.dart';
import '../../l10n/l10n.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/card_sender.dart';
import '../../services/notification_service.dart';
import '../app_layout.dart';
import '../ui_text.dart';
import '../components/saved_cards/card_item.dart';
import '../components/saved_cards/folder_selection_strip.dart';
import '../components/saved_cards/add_card_dialog.dart';
import '../components/saved_cards/add_folder_dialog.dart';
import '../components/instances/select_instance_dialog.dart';

class SavedCardsPage extends HookConsumerWidget {
  const SavedCardsPage({super.key});

  static const double _bottomFloatingBarFabOffset = 88;

  // ---------------------------------------------------------------------------
  // Dialog Actions
  // ---------------------------------------------------------------------------

  void _showAddCardDialog(
    BuildContext context,
    String selectedFolderId,
    ValueSetter<String> onFolderCreated,
  ) {
    if (selectedFolderId == 'history_folder') return;
    showDialog(
      context: context,
      builder: (context) => AddCardDialog(
        initialFolderId: selectedFolderId,
        onAddFolderRequested: () =>
            _showAddFolderDialog(context, onFolderCreated),
      ),
    );
  }

  void _showAddFolderDialog(
    BuildContext context,
    ValueSetter<String> onFolderCreated,
  ) {
    showDialog(
      context: context,
      builder: (context) => AddFolderDialog(onFolderCreated: onFolderCreated),
    );
  }

  void _onDeleteFolder(
    BuildContext context,
    WidgetRef ref,
    CardFolder folder,
    ValueSetter<String> setSelectedFolderId,
  ) {
    if (folder.id == 'history_folder' || folder.id == 'favorites_folder') {
      ref
          .read(notificationServiceProvider)
          .showError(context.l10n.cannotDeleteDefaultFolders);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteFolder),
        content: Text(
          context.l10n.deleteFolderMessage(
            folderDisplayName(context, folder.id, folder.name),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(cardFoldersProvider.notifier).removeFolder(folder.id);
              setSelectedFolderId('favorites_folder');
              Navigator.pop(dialogContext);
            },
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Business Logic
  // ---------------------------------------------------------------------------

  Future<void> _sendCardData(
    BuildContext context,
    WidgetRef ref,
    SavedCard card,
  ) async {
    final selectedInstance = await showDialog<RemoteInstance>(
      context: context,
      builder: (context) => const SelectInstanceDialog(),
    );
    if (selectedInstance == null) return;

    // Create ScanLog for Direct send
    final newLog = ScanLog(
      id: const Uuid().v4(),
      source: 'Direct',
      showValue: card.showValue,
      card: card.card,
      timestamp: DateTime.now(),
    );
    ref.read(scanLogsProvider.notifier).addLog(newLog);

    await ref
        .read(cardSenderProvider.notifier)
        .sendCard(
          card.card,
          targetInstance: selectedInstance,
          triggerId: card.id,
        );
  }

  void _handleSwipe(
    BuildContext context,
    DragEndDetails details,
    List<CardFolder> folders,
    ValueNotifier<String> selectedFolderIdState,
  ) {
    final double velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 300) return;

    final currentFolderIndex = folders.indexWhere(
      (f) => f.id == selectedFolderIdState.value,
    );
    if (currentFolderIndex == -1) return;

    if (velocity > 0) {
      if (currentFolderIndex > 0) {
        selectedFolderIdState.value = folders[currentFolderIndex - 1].id;
      } else {
        context.go('/scan');
      }
    } else {
      if (currentFolderIndex < folders.length - 1) {
        selectedFolderIdState.value = folders[currentFolderIndex + 1].id;
      } else {
        context.go('/settings');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build Method (Flattened)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;
    final selectedFolderIdState = useState('favorites_folder');
    final folders = ref.watch(cardFoldersProvider);
    final allCards = ref.watch(savedCardsProvider);
    final folderCards = allCards
        .where((c) => c.folderId == selectedFolderIdState.value)
        .toList();

    return Scaffold(
      appBar: layout.showPageAppBar ? _buildAppBar(context) : null,
      body: SafeArea(
        top: !layout.showPageAppBar,
        bottom: false,
        child: _buildBody(
          context,
          ref,
          folders,
          selectedFolderIdState,
          folderCards,
        ),
      ),
      floatingActionButton: _buildFABs(
        context,
        selectedFolderIdState,
        bottomPadding: layout.isCompactLandscapePhone
            ? 0
            : _bottomFloatingBarFabOffset,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(title: Text(context.l10n.savedCards));
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<CardFolder> folders,
    ValueNotifier<String> selectedFolderIdState,
    List<SavedCard> folderCards,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth > 700
            ? _SavedCardsWideBody(
                folders: folders,
                selectedFolderId: selectedFolderIdState.value,
                onFolderSelected: (id) => selectedFolderIdState.value = id,
                onFolderLongPress: (folder) => _onDeleteFolder(
                  context,
                  ref,
                  folder,
                  (id) => selectedFolderIdState.value = id,
                ),
                cardsView: _buildCardsView(context, ref, folderCards),
              )
            : _SavedCardsCompactBody(
                onSwipe: (details) => _handleSwipe(
                  context,
                  details,
                  folders,
                  selectedFolderIdState,
                ),
                folderStrip: _buildFolderStrip(
                  context,
                  ref,
                  folders,
                  selectedFolderIdState,
                ),
                cardsView: _buildCardsView(context, ref, folderCards),
              );
      },
    );
  }

  Widget _buildFolderStrip(
    BuildContext context,
    WidgetRef ref,
    List<CardFolder> folders,
    ValueNotifier<String> selectedFolderIdState,
  ) {
    return FolderSelectionStrip(
      folders: folders,
      selectedFolderId: selectedFolderIdState.value,
      onFolderSelected: (id) => selectedFolderIdState.value = id,
      onFolderLongPress: (folder) => _onDeleteFolder(
        context,
        ref,
        folder,
        (id) => selectedFolderIdState.value = id,
      ),
    );
  }

  Widget _buildCardsView(
    BuildContext context,
    WidgetRef ref,
    List<SavedCard> folderCards,
  ) {
    return Expanded(
      child: folderCards.isEmpty
          ? _buildEmptyState(context)
          : _buildCardsList(context, ref, folderCards),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(child: Text(context.l10n.noCardsInFolder));
  }

  Widget _buildCardsList(
    BuildContext context,
    WidgetRef ref,
    List<SavedCard> folderCards,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use MaxCrossAxisExtent for true dynamic columns based on width
        const double maxItemWidth = 380.0;
        final bool isGrid = constraints.maxWidth > maxItemWidth * 1.2;

        if (isGrid) {
          return GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxItemWidth,
              childAspectRatio: 5.0,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
            ),
            itemCount: folderCards.length,
            itemBuilder: (context, index) => CardItem(
              card: folderCards[index],
              onSend: (card) => _sendCardData(context, ref, card),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: folderCards.length,
          itemBuilder: (context, index) => CardItem(
            card: folderCards[index],
            onSend: (card) => _sendCardData(context, ref, card),
          ),
        );
      },
    );
  }

  Widget _buildFABs(
    BuildContext context,
    ValueNotifier<String> selectedFolderIdState, {
    required double bottomPadding,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: _SavedCardsFabGroup(
        showAddCard: selectedFolderIdState.value != 'history_folder',
        onAddFolder: () => _showAddFolderDialog(
          context,
          (newId) => selectedFolderIdState.value = newId,
        ),
        onAddCard: () => _showAddCardDialog(
          context,
          selectedFolderIdState.value,
          (newId) => selectedFolderIdState.value = newId,
        ),
      ),
    );
  }
}

class _SavedCardsWideBody extends StatelessWidget {
  const _SavedCardsWideBody({
    required this.folders,
    required this.selectedFolderId,
    required this.onFolderSelected,
    required this.onFolderLongPress,
    required this.cardsView,
  });

  final List<CardFolder> folders;
  final String selectedFolderId;
  final ValueChanged<String> onFolderSelected;
  final ValueChanged<CardFolder> onFolderLongPress;
  final Widget cardsView;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SavedCardsFolderRail(
          folders: folders,
          selectedFolderId: selectedFolderId,
          onFolderSelected: onFolderSelected,
          onFolderLongPress: onFolderLongPress,
        ),
        const VerticalDivider(width: 1),
        cardsView,
      ],
    );
  }
}

class _SavedCardsCompactBody extends StatelessWidget {
  const _SavedCardsCompactBody({
    required this.onSwipe,
    required this.folderStrip,
    required this.cardsView,
  });

  final GestureDragEndCallback onSwipe;
  final Widget folderStrip;
  final Widget cardsView;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: onSwipe,
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [folderStrip, const Divider(height: 1), cardsView],
      ),
    );
  }
}

class _SavedCardsFolderRail extends StatelessWidget {
  const _SavedCardsFolderRail({
    required this.folders,
    required this.selectedFolderId,
    required this.onFolderSelected,
    required this.onFolderLongPress,
  });

  final List<CardFolder> folders;
  final String selectedFolderId;
  final ValueChanged<String> onFolderSelected;
  final ValueChanged<CardFolder> onFolderLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = folder.id == selectedFolderId;

          return ListTile(
            dense: true,
            selected: isSelected,
            leading: Icon(
              isSelected ? Icons.folder_open : Icons.folder,
              size: 20,
            ),
            title: Text(
              folderDisplayName(context, folder.id, folder.name),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () => onFolderSelected(folder.id),
            onLongPress: () => onFolderLongPress(folder),
          );
        },
      ),
    );
  }
}

class _SavedCardsFabGroup extends StatelessWidget {
  const _SavedCardsFabGroup({
    required this.showAddCard,
    required this.onAddFolder,
    required this.onAddCard,
  });

  final bool showAddCard;
  final VoidCallback onAddFolder;
  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'saved_cards_new_folder',
          onPressed: onAddFolder,
          tooltip: context.l10n.newFolder,
          icon: const Icon(Icons.create_new_folder),
          label: Text(context.l10n.newFolder),
        ),
        if (showAddCard) ...[
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'saved_cards_new_card',
            onPressed: onAddCard,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.addCard),
          ),
        ],
      ],
    );
  }
}
