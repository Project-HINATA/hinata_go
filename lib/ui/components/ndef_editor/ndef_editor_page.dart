import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:uuid/uuid.dart';

import '../../../l10n/l10n.dart';
import '../../../models/card/ndef.dart';
import '../../../models/card/ndef_record_draft.dart';
import '../../../models/card/saved_card.dart';
import '../../../providers/app_state_provider.dart';
import '../../../services/notification_service.dart';
import '../../ndef_record_ui.dart';
import '../../ui_text.dart';
import '../../widgets/native_alert.dart';
import 'editor_widgets.dart';
import 'ndef_record_page.dart';

/// Edits [savedCard], or makes a new dataset, starting from the records of
/// [copyOf] when given.
Future<void> showNdefEditor(
  BuildContext context, {
  required String initialFolderId,
  SavedCard? savedCard,
  NdefCard? copyOf,
  String? initialName,
}) async {
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => NdefEditorPage(
        initialFolderId: initialFolderId,
        savedCard: savedCard,
        copyOf: copyOf,
        initialName: initialName,
      ),
    ),
  );
}

/// A record in the editor's list, with a key that follows it as it moves.
typedef _Entry = ({int key, ndef.NDEFRecord record});

class NdefEditorPage extends HookConsumerWidget {
  const NdefEditorPage({
    super.key,
    required this.initialFolderId,
    this.savedCard,
    this.copyOf,
    this.initialName,
  });

  final String initialFolderId;
  final SavedCard? savedCard;

  /// The NDEF a new dataset starts from. The dataset does not take its
  /// physical card, so it is emulated as a tag of its own.
  final NdefCard? copyOf;
  final String? initialName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = savedCard?.card as NdefCard?;
    final startName = savedCard?.name ?? initialName ?? copyOf?.name ?? '';
    final startRecords = useMemoized(
      () => original?.records ?? copyOf?.records ?? <ndef.NDEFRecord>[],
    );
    final startMessage = useMemoized(() => _encode(startRecords));

    final name = useTextEditingController(text: startName);
    useListenable(name);
    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != SavedCardsNotifier.historyFolderId)
        .toList();
    final folder = useState(
      folders.any((f) => f.id == initialFolderId)
          ? initialFolderId
          : folders.firstOrNull?.id ?? initialFolderId,
    );
    final nextKey = useRef(0);
    _Entry entry(ndef.NDEFRecord record) =>
        (key: nextKey.value++, record: record);
    final entries = useState<List<_Entry>>(
      useMemoized(() => [for (final record in startRecords) entry(record)]),
    );
    final showErrors = useState(false);

    final records = [for (final e in entries.value) e.record];
    final size = ndefMessageSize(records);
    final dirty =
        name.text != startName ||
        folder.value != (savedCard?.folderId ?? initialFolderId) ||
        !listEquals(_encode(records), startMessage);

    Future<void> add() async {
      final outcome = await showNdefKindPicker(context);
      if (outcome is NdefRecordSaved) {
        entries.value = [...entries.value, entry(outcome.record)];
      }
    }

    Future<void> edit(int index) async {
      final current = entries.value[index];
      final outcome = await showNdefRecordPage(context, record: current.record);
      final updated = [...entries.value];
      final at = updated.indexWhere((e) => e.key == current.key);
      if (at < 0) return;
      switch (outcome) {
        case NdefRecordSaved(:final record):
          updated[at] = (key: current.key, record: record);
        case NdefRecordDeleted():
          updated.removeAt(at);
        case null:
          return;
      }
      entries.value = updated;
    }

    void reorder(int from, int to) {
      final updated = [...entries.value];
      final moved = updated.removeAt(from);
      updated.insert(to, moved);
      entries.value = updated;
    }

    void save() {
      final trimmed = name.text.trim();
      if (trimmed.isEmpty || records.isEmpty) {
        showErrors.value = true;
        return;
      }
      try {
        final card = NdefCard(
          ndef.encodeNdefMessage(records),
          tags: original?.tags ?? [],
          physicalCard: original?.physicalCard,
          capacity: original?.capacity,
        );
        final notifier = ref.read(savedCardsProvider.notifier);
        if (savedCard != null) {
          notifier.updateCard(
            savedCard!.copyWith(
              name: trimmed,
              card: card,
              folderId: folder.value,
            ),
          );
        } else {
          notifier.addCard(
            SavedCard(
              id: const Uuid().v4(),
              name: trimmed,
              card: card,
              folderId: folder.value,
            ),
          );
        }
        Navigator.of(context).pop();
      } catch (e, s) {
        log('Saving the NDEF dataset failed', error: e, stackTrace: s);
        ref.read(notificationServiceProvider).showError(l10n.ndefInvalidRecord);
      }
    }

    return DiscardGuard(
      dirty: dirty,
      child: EditorPage(
        title: savedCard == null ? l10n.ndefCreate : l10n.ndefEdit,
        closes: true,
        button: EditorPrimaryButton(
          label: l10n.save,
          icon: Icons.check_rounded,
          onPressed: save,
        ),
        children: [
          _DetailsSection(
            name: name,
            nameError: showErrors.value && name.text.trim().isEmpty,
            folders: [
              for (final f in folders)
                NativeChoice(
                  label: folderDisplayName(f.id, f.name),
                  value: f.id,
                ),
            ],
            folder: folder.value,
            onFolderChanged: (value) => folder.value = value,
          ),
          const SizedBox(height: 16),
          _RecordsSection(
            entries: entries.value,
            size: size,
            missing: showErrors.value && records.isEmpty,
            onAdd: add,
            onEdit: edit,
            onReorder: reorder,
          ),
          if (records.length > 1) ...[
            const SizedBox(height: 12),
            EditorNote(l10n.ndefOrderHint),
          ],
        ],
      ),
    );
  }
}

Uint8List _encode(List<ndef.NDEFRecord> records) =>
    records.isEmpty ? Uint8List(0) : ndef.encodeNdefMessage(records);

/// The dataset's name and the folder it is saved to, as the header of the
/// card detail.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({
    required this.name,
    required this.nameError,
    required this.folders,
    required this.folder,
    required this.onFolderChanged,
  });

  final TextEditingController name;
  final bool nameError;
  final List<NativeChoice<String>> folders;
  final String folder;
  final ValueChanged<String> onFolderChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const EditorIconBadge(icon: Icons.nfc, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: name,
                    textInputAction: TextInputAction.done,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.ndefName,
                      hintStyle: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      errorText: nameError ? l10n.ndefFieldRequired : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: EditorChoiceRow(
              icon: Icons.folder_outlined,
              label: l10n.ndefFolder,
              child: EditorMenuChoice<String>(
                options: folders,
                selected: folder,
                onChanged: onFolderChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordsSection extends StatelessWidget {
  const _RecordsSection({
    required this.entries,
    required this.size,
    required this.missing,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
  });

  final List<_Entry> entries;
  final int size;
  final bool missing;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final divider = Divider(
      height: 1,
      color: colors.outlineVariant.withValues(alpha: 0.5),
    );
    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorSectionHeader(
            icon: Icons.list_alt_rounded,
            title: l10n.ndefRecordsTitle,
            pill: entries.isEmpty ? null : l10n.ndefBytes(size),
          ),
          divider,
          if (entries.isEmpty)
            _EmptyRecords(missing: missing)
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: onReorder,
              proxyDecorator: (child, index, animation) => Material(
                color: colors.surfaceContainerHigh,
                elevation: 6,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
              children: [
                for (final (index, entry) in entries.indexed)
                  _RecordRow(
                    key: ValueKey(entry.key),
                    index: index,
                    record: entry.record,
                    showDivider: index > 0,
                    reorderable: entries.length > 1,
                    onTap: () => onEdit(index),
                  ),
              ],
            ),
          divider,
          InkWell(
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.ndefAddRecord,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords({required this.missing});

  /// Whether saving was tried without a record.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = missing ? colors.error : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Icon(Icons.nfc, size: 36, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            missing ? l10n.ndefRecordsMissing : l10n.ndefRecordsEmpty,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: missing ? colors.error : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.ndefRecordsEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    super.key,
    required this.index,
    required this.record,
    required this.showDivider,
    required this.reorderable,
    required this.onTap,
  });

  final int index;
  final ndef.NDEFRecord record;
  final bool showDivider;
  final bool reorderable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final value = ndefRecordSummary(record);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent: 64,
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Row(
              children: [
                EditorIconBadge(icon: ndefRecordIcon(record)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ndefRecordLabel(record),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (value.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (reorderable)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.chevron_right,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
