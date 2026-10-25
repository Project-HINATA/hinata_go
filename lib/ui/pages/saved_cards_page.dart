import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/card/saved_card.dart';
import '../../models/card_folder.dart';
import '../../models/remote_instance.dart';
import '../../models/scan_log.dart';
import '../../l10n/l10n.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/card_sender.dart';
import '../../providers/navigation_bar_provider.dart';
import '../../services/notification_service.dart';
import '../app_layout.dart';
import '../ui_text.dart';
import '../components/saved_cards/card_item.dart';
import '../components/saved_cards/folder_selection_strip.dart';
import '../components/saved_cards/add_card_dialog.dart';
import '../components/saved_cards/add_felica_dialog.dart';
import '../components/saved_cards/ndef_editor_dialog.dart';
import '../components/saved_cards/add_folder_dialog.dart';
import '../components/instances/select_instance_dialog.dart';
import '../app_action_button.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/native_alert.dart';

class SavedCardsPage extends ConsumerWidget {
  const SavedCardsPage({super.key});

  // ---------------------------------------------------------------------------
  // Dialog Actions
  // ---------------------------------------------------------------------------

  void _showAddCardDialog(
    BuildContext context,
    String selectedFolderId,
    ValueSetter<String> onFolderCreated,
  ) {
    showDialog(
      context: context,
      builder: (context) => AddCardDialog(
        initialFolderId: selectedFolderId,
        onAddFolderRequested: () =>
            _showAddFolderDialog(context, onFolderCreated),
      ),
    );
  }

  void _showAddFelicaDialog(
    BuildContext context,
    String selectedFolderId,
    ValueSetter<String> onFolderCreated,
  ) {
    showDialog(
      context: context,
      builder: (context) => AddFelicaDialog(
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
          .showError(l10n.cannotDeleteDefaultFolders);
      return;
    }
    void deleteFolder() {
      ref.read(cardFoldersProvider.notifier).removeFolder(folder.id);
      setSelectedFolderId('favorites_folder');
    }

    final message = l10n.deleteFolderMessage(
      folderDisplayName(folder.id, folder.name),
    );
    if (useCupertinoChrome) {
      showNativeConfirmation(
        context,
        title: l10n.deleteFolder,
        message: message,
        confirmLabel: l10n.delete,
        destructive: true,
      ).then((confirmed) {
        if (confirmed) deleteFolder();
      });
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteFolder),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              deleteFolder();
              Navigator.pop(dialogContext);
            },
            child: Text(l10n.delete),
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

  // ---------------------------------------------------------------------------
  // Build Method (Flattened)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFolderId = ref.watch(selectedCardFolderIdProvider);
    final layout = context.appLayout;
    final folders = ref.watch(cardFoldersProvider);
    final allCards = ref.watch(savedCardsProvider);
    final folderCards = allCards
        .where((c) => c.folderId == selectedFolderId)
        .toList();
    void selectFolder(String id) {
      ref.read(selectedCardFolderIdProvider.notifier).select(id);
    }

    // Beside the folder rail, which already lists the folders, there are no
    // chips.
    final wide = ref.watch(cardsWideLayoutProvider);

    return AppScaffold(
      title: l10n.savedCards,
      largeTitle: true,
      chips: wide
          ? null
          : [
              for (final folder in folders)
                AdaptiveToolbarChip(
                  label: folderDisplayName(folder.id, folder.name),
                  selected: folder.id == selectedFolderId,
                  onPressed: () => selectFolder(folder.id),
                  onLongPress: () =>
                      _onDeleteFolder(context, ref, folder, selectFolder),
                ),
            ],
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildBody(
          context,
          ref,
          layout,
          folders,
          selectedFolderId,
          folderCards,
        ),
      ),
      primaryAction: AppActionConfig(
        id: 'cardsAction',
        icon: Icons.add,
        tooltip: l10n.addCard,
        nativeSymbol: 'plus',
        // The history folder holds scans, not cards the user files by hand.
        // Its entries never mix in: adding always asks for a folder, and that
        // picker leaves history out, so the action stays available here instead
        // of the page hiding its whole toolbar.
        menuItems: [
          AppActionItem(
            id: 'addCard',
            label: l10n.addAimeBanapass,
            icon: Icons.add,
            nativeSymbol: 'creditcard',
            onPressed: () =>
                _showAddCardDialog(context, selectedFolderId, selectFolder),
            onLongPress: () =>
                _showAddFelicaDialog(context, selectedFolderId, selectFolder),
          ),
          AppActionItem(
            id: 'addNdef',
            label: l10n.ndefCreate,
            icon: Icons.nfc,
            nativeSymbol: 'wave.3.right',
            onPressed: () =>
                showNdefEditor(context, initialFolderId: selectedFolderId),
          ),
          AppActionItem(
            id: 'addFolder',
            label: l10n.newFolder,
            icon: Icons.create_new_folder,
            nativeSymbol: 'folder.badge.plus',
            onPressed: () => _showAddFolderDialog(context, selectFolder),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLayoutInfo layout,
    List<CardFolder> folders,
    String selectedFolderId,
    List<SavedCard> folderCards,
  ) {
    void selectFolder(String id) {
      ref.read(selectedCardFolderIdProvider.notifier).select(id);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        if (wide != ref.read(cardsWideLayoutProvider)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ref.read(cardsWideLayoutProvider.notifier).setWide(wide);
          });
        }
        final folderStrip = _buildFolderStrip(
          context,
          ref,
          folders,
          selectedFolderId,
          selectFolder,
        );
        if (!wide && TopBarAccessoryScope.isNative(context)) {
          // The bar shows the folders as glass chips; the cards scroll
          // underneath them, the large title and the bar.
          return _SavedCardsScrollBody(
            cards: _buildCardsSliver(context, ref, folderCards),
          );
        }
        // Under the native bar the two columns of the wide layout pad
        // themselves and scroll beneath its glass; the compact one keeps its
        // folder strip below the bar.
        final underNativeBar =
            wide &&
            (ToolbarChromeScope.maybeOf(context)?.nativeTopBarOwned ?? false);
        return SafeArea(
          top: !underNativeBar && (layout.isLandscape || useCupertinoChrome),
          bottom: useCupertinoChrome,
          left: false,
          right: false,
          child: wide
              ? _SavedCardsWideBody(
                  folders: folders,
                  selectedFolderId: selectedFolderId,
                  onFolderSelected: selectFolder,
                  onFolderLongPress: (folder) =>
                      _onDeleteFolder(context, ref, folder, selectFolder),
                  cardsView: _buildCardsView(context, ref, folderCards),
                )
              : _SavedCardsCompactBody(
                  folderStrip: folderStrip,
                  cardsView: _buildCardsView(context, ref, folderCards),
                ),
        );
      },
    );
  }

  Widget _buildFolderStrip(
    BuildContext context,
    WidgetRef ref,
    List<CardFolder> folders,
    String selectedFolderId,
    ValueSetter<String> selectFolder,
  ) {
    return FolderSelectionStrip(
      folders: folders,
      selectedFolderId: selectedFolderId,
      onFolderSelected: selectFolder,
      onFolderLongPress: (folder) =>
          _onDeleteFolder(context, ref, folder, selectFolder),
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
    return Center(child: Text(l10n.noCardsInFolder));
  }

  // Use MaxCrossAxisExtent for true dynamic columns based on width
  static const double _maxCardItemWidth = 380.0;
  static const _cardsGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: _maxCardItemWidth,
    childAspectRatio: 5.0,
    mainAxisSpacing: 0,
    crossAxisSpacing: 0,
  );

  static bool _cardsUseGrid(double width) => width > _maxCardItemWidth * 1.2;

  /// The folder's cards as slivers, for the page that scrolls as a whole.
  Widget _buildCardsSliver(
    BuildContext context,
    WidgetRef ref,
    List<SavedCard> folderCards,
  ) {
    if (folderCards.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(context),
      );
    }
    Widget buildItem(BuildContext context, int index) => CardItem(
      card: folderCards[index],
      onSend: (card) => _sendCardData(context, ref, card),
    );
    return SliverLayoutBuilder(
      builder: (context, constraints) =>
          _cardsUseGrid(constraints.crossAxisExtent)
          ? SliverGrid.builder(
              gridDelegate: _cardsGridDelegate,
              itemCount: folderCards.length,
              itemBuilder: buildItem,
            )
          : SliverList.builder(
              itemCount: folderCards.length,
              itemBuilder: buildItem,
            ),
    );
  }

  Widget _buildCardsList(
    BuildContext context,
    WidgetRef ref,
    List<SavedCard> folderCards,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_cardsUseGrid(constraints.maxWidth)) {
          return GridView.builder(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            gridDelegate: _cardsGridDelegate,
            itemCount: folderCards.length,
            itemBuilder: (context, index) => CardItem(
              card: folderCards[index],
              onSend: (card) => _sendCardData(context, ref, card),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          itemCount: folderCards.length,
          itemBuilder: (context, index) => CardItem(
            card: folderCards[index],
            onSend: (card) => _sendCardData(context, ref, card),
          ),
        );
      },
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
    required this.folderStrip,
    required this.cardsView,
  });

  final Widget folderStrip;
  final Widget cardsView;

  @override
  Widget build(BuildContext context) {
    return Column(children: [folderStrip, const Divider(height: 1), cardsView]);
  }
}

/// The compact layout under the native bar's folder chips: the cards alone,
/// inset by the bar, the large title and the chips above them.
class _SavedCardsScrollBody extends StatelessWidget {
  const _SavedCardsScrollBody({required this.cards});

  final Widget cards;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          sliver: cards,
        ),
      ],
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
    // The cards list beside the rail is the page's scroll, which the large
    // title and the bar's glass follow; the rail must not be taken for it.
    return _ScrollNotReported(
      child: SizedBox(
        width: 180,
        child: ListView.builder(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 8,
            bottom: 8,
          ),
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
                folderDisplayName(folder.id, folder.name),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () => onFolderSelected(folder.id),
              onLongPress: () => onFolderLongPress(folder),
            );
          },
        ),
      ),
    );
  }
}

/// Keeps the scrolling of [child] from the scaffold, which follows the
/// page's main scroll view for the large title and the bar's glass.
class _ScrollNotReported extends StatelessWidget {
  const _ScrollNotReported({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) => true,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: child,
      ),
    );
  }
}
