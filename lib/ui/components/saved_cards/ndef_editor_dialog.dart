import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:uuid/uuid.dart';

import '../../../l10n/l10n.dart';
import '../../../models/card/ndef.dart';
import '../../../models/card/saved_card.dart';
import '../../../providers/app_state_provider.dart';
import '../../ui_text.dart';
import '../../ndef_record_ui.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/native_alert.dart';

Future<void> showNdefEditor(
  BuildContext context, {
  required String initialFolderId,
  SavedCard? savedCard,
}) async {
  await _showEditorRoute<void>(
    context,
    (_) => NdefEditorDialog(
      initialFolderId: initialFolderId,
      savedCard: savedCard,
    ),
  );
}

Future<T?> _showEditorRoute<T>(BuildContext context, WidgetBuilder builder) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<T>(MaterialPageRoute<T>(fullscreenDialog: true, builder: builder));
  }
  return showDialog<T>(context: context, builder: builder);
}

class NdefEditorDialog extends HookConsumerWidget {
  final String initialFolderId;
  final SavedCard? savedCard;
  const NdefEditorDialog({
    super.key,
    required this.initialFolderId,
    this.savedCard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = useTextEditingController(text: savedCard?.name ?? 'NDEF');
    useListenable(name);
    final folder = useState(initialFolderId);
    final records = useState(
      (savedCard?.card as NdefCard?)?.records ?? <ndef.NDEFRecord>[],
    );
    final folders = ref
        .watch(cardFoldersProvider)
        .where((f) => f.id != 'history_folder')
        .toList();
    final error = useState<String?>(null);
    Future<void> edit([int? index]) async {
      final record = await _showEditorRoute<ndef.NDEFRecord>(
        context,
        (_) =>
            _RecordDialog(record: index == null ? null : records.value[index]),
      );
      if (record == null) return;
      final updated = [...records.value];
      if (index == null) {
        updated.add(record);
      } else {
        updated[index] = record;
      }
      records.value = updated;
    }

    return _EditorFrame(
      title: savedCard == null ? l10n.ndefCreate : l10n.ndefEdit,
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: l10n.ndefName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              NativeChoiceField<String>(
                label: l10n.ndefFolder,
                options: [
                  for (final f in folders)
                    NativeChoice(
                      label: folderDisplayName(f.id, f.name),
                      value: f.id,
                    ),
                ],
                selected: folder.value,
                onChanged: (value) => folder.value = value,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < records.value.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(ndefRecordIcon(records.value[i])),
                  title: Text(
                    ndefRecordLabel(records.value[i]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    ndefRecordValue(records.value[i]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => edit(i),
                  trailing: IconButton(
                    tooltip: l10n.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        records.value = [...records.value]..removeAt(i),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: edit,
                icon: const Icon(Icons.add),
                label: Text(l10n.ndefAddRecord),
              ),
              if (error.value != null)
                Text(
                  error.value!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: name.text.trim().isEmpty || records.value.isEmpty
              ? null
              : () {
                  try {
                    final original = savedCard?.card as NdefCard?;
                    final card = NdefCard(
                      ndef.encodeNdefMessage(records.value),
                      tags: original?.tags ?? [],
                      physicalCard: original?.physicalCard,
                      capacity: original?.capacity,
                    );
                    final notifier = ref.read(savedCardsProvider.notifier);
                    if (savedCard != null) {
                      notifier.updateCard(
                        savedCard!.copyWith(
                          name: name.text.trim(),
                          card: card,
                          folderId: folder.value,
                        ),
                      );
                    } else {
                      notifier.addCard(
                        SavedCard(
                          id: const Uuid().v4(),
                          name: name.text.trim(),
                          card: card,
                          folderId: folder.value,
                        ),
                      );
                    }
                    Navigator.pop(context);
                  } catch (_) {
                    error.value = l10n.ndefInvalidRecord;
                  }
                },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _RecordDialog extends HookWidget {
  final ndef.NDEFRecord? record;
  const _RecordDialog({this.record});

  @override
  Widget build(BuildContext context) {
    final uri = record == null ? null : ndefRecordUri(record!);
    ndef.TextRecord? textRecord;
    if (record != null) {
      try {
        final decoded = ndef.NDEFRecord.doDecode(
          record!.tnf,
          record!.type!,
          record!.payload!,
          id: record!.id,
        );
        if (decoded is ndef.TextRecord) textRecord = decoded;
      } catch (_) {
        /* Keep unrecognized records in the raw editor. */
      }
    }
    String? editablePayload;
    String? editableType;
    if (record != null &&
        (record!.tnf == ndef.TypeNameFormat.media ||
            record!.tnf == ndef.TypeNameFormat.nfcExternal)) {
      try {
        final decoded = utf8.decode(record!.payload!);
        final decodedType = utf8.decode(record!.type!);
        if (!decoded.runes.any((r) => r < 32 && r != 9 && r != 10 && r != 13)) {
          final validType = record!.tnf == ndef.TypeNameFormat.media
              ? RegExp(
                  r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$',
                  caseSensitive: false,
                ).hasMatch(decodedType)
              : RegExp(
                  r'^[a-z0-9.-]+:[a-z0-9._-]+$',
                  caseSensitive: false,
                ).hasMatch(decodedType);
          if (validType) {
            editablePayload = decoded;
            editableType = decodedType;
          }
        }
      } on FormatException {
        // Binary payloads must remain in the lossless raw editor.
      }
    }
    final kind = useState(
      record == null
          ? 'text'
          : uri != null
          ? 'url'
          : textRecord != null
          ? 'text'
          : editablePayload != null
          ? (record!.tnf == ndef.TypeNameFormat.media ? 'mime' : 'external')
          : 'raw',
    );
    final content = useTextEditingController(
      text: uri?.toString() ?? textRecord?.text ?? editablePayload ?? '',
    );
    final type = useTextEditingController(text: editableType ?? '');
    final language = useTextEditingController(
      text:
          textRecord?.language ?? Localizations.localeOf(context).languageCode,
    );
    final rawType = useTextEditingController(text: _hex(record?.type ?? []));
    final rawPayload = useTextEditingController(
      text: _hex(record?.payload ?? []),
    );
    final id = useTextEditingController(text: _hex(record?.id ?? []));
    final tnf = useState(record?.tnf ?? ndef.TypeNameFormat.unknown);
    final error = useState<String?>(null);
    return _EditorFrame(
      title: record == null ? l10n.ndefRecordAdd : l10n.ndefRecordEdit,
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NativeChoiceField<String>(
                label: l10n.ndefRecordKind,
                options: [
                  NativeChoice(label: l10n.ndefText, value: 'text'),
                  NativeChoice(label: l10n.ndefLink, value: 'url'),
                  const NativeChoice(label: 'MIME', value: 'mime'),
                  NativeChoice(label: l10n.ndefExternal, value: 'external'),
                  NativeChoice(label: l10n.ndefRaw, value: 'raw'),
                ],
                selected: kind.value,
                onChanged: (value) {
                  kind.value = value;
                  error.value = null;
                },
              ),
              const SizedBox(height: 20),
              if (kind.value == 'raw') ...[
                NativeChoiceField<ndef.TypeNameFormat>(
                  label: l10n.ndefTnf,
                  options: [
                    for (final v in ndef.TypeNameFormat.values)
                      if (v != ndef.TypeNameFormat.unchanged)
                        NativeChoice(label: ndefTnfLabel(v), value: v),
                  ],
                  selected: tnf.value,
                  onChanged: (value) => tnf.value = value,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: rawType,
                  decoration: InputDecoration(
                    labelText: l10n.ndefTypeHex,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: rawPayload,
                  maxLines: 5,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.ndefPayloadHex,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                if (kind.value == 'mime' || kind.value == 'external')
                  TextField(
                    controller: type,
                    decoration: InputDecoration(
                      labelText: kind.value == 'mime'
                          ? l10n.ndefMimeType
                          : l10n.ndefExternalTypeName,
                      hintText: kind.value == 'mime'
                          ? 'application/json, text/vcard'
                          : 'example.com:record',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (kind.value == 'mime' || kind.value == 'external')
                  const SizedBox(height: 20),
                if (kind.value == 'text')
                  TextField(
                    controller: language,
                    decoration: InputDecoration(
                      labelText: l10n.ndefLanguage,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (kind.value == 'text') const SizedBox(height: 20),
                TextField(
                  controller: content,
                  maxLines: 5,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.ndefContent,
                    helperText: kind.value == 'url' ? l10n.ndefLinkHint : null,
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: id.text.isNotEmpty,
                title: Text(l10n.ndefAdvanced),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: TextField(
                      controller: id,
                      decoration: InputDecoration(
                        labelText: l10n.ndefIdHex,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              if (error.value != null)
                Text(
                  error.value!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            try {
              late final ndef.NDEFRecord result;
              switch (kind.value) {
                case 'url':
                  final uri = Uri.tryParse(content.text.trim());
                  if (uri == null || !uri.hasScheme) {
                    throw const FormatException();
                  }
                  result = ndef.UriRecord.fromString(uri.toString());
                case 'text':
                  if (!RegExp(
                        r'^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$',
                      ).hasMatch(language.text) ||
                      language.text.length > 63) {
                    throw const FormatException();
                  }
                  result = ndef.TextRecord(
                    text: content.text,
                    language: language.text,
                  );
                case 'mime':
                case 'external':
                  final value = type.text.trim().toLowerCase();
                  if (!(kind.value == 'mime'
                          ? RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$')
                          : RegExp(r'^[a-z0-9.-]+:[a-z0-9._-]+$'))
                      .hasMatch(value)) {
                    throw const FormatException();
                  }
                  result = ndef.NDEFRecord(
                    tnf: kind.value == 'mime'
                        ? ndef.TypeNameFormat.media
                        : ndef.TypeNameFormat.nfcExternal,
                    type: Uint8List.fromList(utf8.encode(value)),
                    payload: Uint8List.fromList(utf8.encode(content.text)),
                  );
                default:
                  result = ndef.NDEFRecord(
                    tnf: tnf.value,
                    type: _unhex(rawType.text),
                    payload: _unhex(rawPayload.text),
                  );
              }
              final identifier = _unhex(id.text);
              result.id = identifier.isEmpty ? null : identifier;
              if ((result.type?.length ?? 0) > 255 ||
                  (result.id?.length ?? 0) > 255) {
                throw const FormatException();
              }
              NdefCard.fromRecords([result]);
              Navigator.pop(context, result);
            } catch (_) {
              error.value = l10n.ndefInvalidRecord;
            }
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _EditorFrame extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const _EditorFrame({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return AlertDialog(
        title: Text(title),
        content: content,
        actions: actions,
      );
    }
    final primaryAction = SizedBox(
      height: 48,
      child: FilledButtonTheme(
        data: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        child: actions.last,
      ),
    );
    if (useCupertinoChrome) {
      return AppScaffold(
        title: title,
        nativeLeading: NativeToolbarLeading.close,
        onNativeLeadingTap: () => Navigator.pop(context),
        // A full-size round glass control, like the close and back buttons the
        // system puts in the toolbar; the 38pt default reads one size small.
        leading: SizedBox.square(
          dimension: 48,
          child: AdaptiveButton.sfSymbol(
            onPressed: () => Navigator.pop(context),
            sfSymbol: const SFSymbol('xmark', size: 20),
            size: AdaptiveButtonSize.large,
            useSmoothRectangleBorder: false,
          ),
        ),
        body: SafeArea(
          minimum: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: content,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: primaryAction,
              ),
            ],
          ),
        ),
      );
    }
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.cancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Padding(padding: const EdgeInsets.all(24), child: content),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: primaryAction,
          ),
        ),
      ),
    );
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
Uint8List _unhex(String value) {
  final clean = value.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^(?:[0-9a-fA-F]{2})*$').hasMatch(clean)) {
    throw const FormatException('Invalid hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
