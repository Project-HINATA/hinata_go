import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../../../l10n/l10n.dart';
import '../../../models/card/ndef_presets.dart';
import '../../../models/card/ndef_record_draft.dart';
import '../../ndef_record_ui.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/native_alert.dart';
import 'editor_widgets.dart';

/// What the record page ends with: the record made, or the record deleted.
sealed class NdefRecordOutcome {
  const NdefRecordOutcome();
}

class NdefRecordSaved extends NdefRecordOutcome {
  const NdefRecordSaved(this.record);

  final ndef.NDEFRecord record;
}

class NdefRecordDeleted extends NdefRecordOutcome {
  const NdefRecordDeleted();
}

/// Opens the form of [record], or of a new record of [kind].
Future<NdefRecordOutcome?> showNdefRecordPage(
  BuildContext context, {
  ndef.NDEFRecord? record,
  NdefRecordKind? kind,
}) {
  final language = Localizations.localeOf(context).languageCode;
  final draft = record != null
      ? NdefRecordDraft.fromRecord(record, language: language)
      : NdefRecordDraft.empty(kind!, language: language);
  return Navigator.of(context).push<NdefRecordOutcome>(
    MaterialPageRoute(
      builder: (_) => NdefRecordPage(initial: draft, isNew: record == null),
    ),
  );
}

/// Picks the kind of a new record, then opens its form.
Future<NdefRecordOutcome?> showNdefKindPicker(BuildContext context) {
  return Navigator.of(context).push<NdefRecordOutcome>(
    MaterialPageRoute(builder: (_) => const _KindPickerPage()),
  );
}

class _KindPickerPage extends StatelessWidget {
  const _KindPickerPage();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    Future<void> pick(NdefRecordKind kind) async {
      final outcome = await showNdefRecordPage(context, kind: kind);
      if (outcome != null && context.mounted) Navigator.pop(context, outcome);
    }

    return AppScaffold(
      title: l10n.ndefChooseKind,
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + media.padding.top,
            20,
            20 + media.padding.bottom,
          ),
          children: [
            for (final (title, advanced) in [
              (l10n.ndefKindsCommon, false),
              (l10n.ndefKindsAdvanced, true),
            ]) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(8, advanced ? 24 : 0, 8, 12),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              EditorSection(
                child: Column(
                  children: [
                    for (final (index, kind) in [
                      for (final kind in NdefRecordKind.values)
                        if (kind.isAdvanced == advanced) kind,
                    ].indexed) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      _KindRow(kind: kind, onTap: () => pick(kind)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({required this.kind, required this.onTap});

  final NdefRecordKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            EditorIconBadge(icon: ndefKindIcon(kind)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ndefKindLabel(kind),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ndefKindDescription(kind),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The form of one record.
class NdefRecordPage extends HookWidget {
  const NdefRecordPage({super.key, required this.initial, required this.isNew});

  final NdefRecordDraft initial;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final kind = initial.kind;
    final controllers = useMemoized(
      () => {
        for (final field in kind.fields)
          field: TextEditingController(text: initial.valueOf(field)),
      },
    );
    useEffect(
      () => () {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      },
      const [],
    );
    useListenable(
      useMemoized(() => Listenable.merge(controllers.values.toList())),
    );
    final security = useState(initial.security);
    final tnf = useState(initial.tnf);
    final showErrors = useState(false);
    final saveError = useState(false);

    // Read from the fields each time: a tap can land before the frame that
    // shows the latest text.
    NdefRecordDraft current() => initial.copyWith(
      values: {
        for (final MapEntry(:key, :value) in controllers.entries)
          key: value.text,
      },
      security: security.value,
      tnf: tnf.value,
    );
    final draft = current();
    final errors = draft.errors;
    final dirty =
        security.value != initial.security ||
        tnf.value != initial.tnf ||
        controllers.entries.any((e) => e.value.text != initial.valueOf(e.key));

    // Fields are flagged once saving was tried, not while they are typed.
    String? errorOf(NdefField field) => switch (errors[field]) {
      final error? when showErrors.value => ndefFieldErrorText(field, error),
      _ => null,
    };

    void done() {
      final latest = current();
      if (latest.errors.isNotEmpty) {
        showErrors.value = true;
        return;
      }
      try {
        Navigator.of(context).pop(NdefRecordSaved(latest.toRecord()));
      } catch (e, s) {
        log('Making the NDEF record failed', error: e, stackTrace: s);
        saveError.value = true;
      }
    }

    void delete() => Navigator.of(context).pop(const NdefRecordDeleted());

    Widget field(NdefField field) => EditorTextField(
      controller: controllers[field]!,
      label: field.requiredIn(kind) || field == NdefField.password
          ? ndefFieldLabel(field, kind)
          : '${ndefFieldLabel(field, kind)} · ${l10n.ndefFieldOptional}',
      placeholder: ndefFieldPlaceholder(field, kind),
      helper: _helperOf(field, kind),
      error: errorOf(field),
      multiline: const {
        NdefField.text,
        NdefField.body,
        NdefField.content,
        NdefField.payload,
      }.contains(field),
      monospace:
          (kind == NdefRecordKind.raw && field == NdefField.type) ||
          field == NdefField.payload ||
          field == NdefField.id,
      keyboardType: _keyboardOf(field),
    );

    final form = <Widget>[
      if (kind == NdefRecordKind.raw)
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
      for (final f in draft.fields) ...[
        field(f),
        if (kind == NdefRecordKind.wifi && f == NdefField.ssid)
          _LabelledChoice(
            label: l10n.ndefWifiSecurity,
            child: _SecurityPicker(
              selected: security.value,
              onChanged: (value) => security.value = value,
            ),
          ),
      ],
    ];

    return DiscardGuard(
      dirty: dirty,
      child: EditorPage(
        title: isNew ? l10n.ndefRecordAdd : l10n.ndefRecordEdit,
        actions: [
          if (!isNew)
            AdaptiveAppBarAction(
              iosSymbol: 'trash',
              icon: Icons.delete_outline,
              label: l10n.ndefRecordDelete,
              onPressed: delete,
            ),
        ],
        button: EditorPrimaryButton(
          label: l10n.ndefRecordDone,
          icon: Icons.check_rounded,
          onPressed: done,
        ),
        children: [
          EditorSection(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  EditorIconBadge(icon: ndefKindIcon(kind), size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ndefKindLabel(kind),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ndefKindDescription(kind),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          EditorSection(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, widget) in form.indexed) ...[
                    if (index > 0) const SizedBox(height: 18),
                    widget,
                  ],
                ],
              ),
            ),
          ),
          if (_noteOf(kind) case final note?) ...[
            const SizedBox(height: 16),
            EditorNote(note),
          ],
          if (saveError.value) ...[
            const SizedBox(height: 16),
            EditorNote(l10n.ndefInvalidRecord, icon: Icons.error_outline),
          ],
        ],
      ),
    );
  }
}

String? _helperOf(NdefField field, NdefRecordKind kind) => switch (field) {
  NdefField.url => l10n.ndefLinkHint,
  NdefField.password => l10n.ndefWifiPasswordShort,
  NdefField.language => l10n.ndefLanguageHint,
  NdefField.payload => l10n.ndefHexHint,
  NdefField.type when kind == NdefRecordKind.raw => l10n.ndefHexHint,
  _ => null,
};

String? _noteOf(NdefRecordKind kind) => switch (kind) {
  NdefRecordKind.wifi => l10n.ndefWifiHint,
  NdefRecordKind.androidApp => l10n.ndefAndroidAppHint,
  _ => null,
};

TextInputType? _keyboardOf(NdefField field) => switch (field) {
  NdefField.url => TextInputType.url,
  NdefField.phone => TextInputType.phone,
  NdefField.email => TextInputType.emailAddress,
  NdefField.latitude || NdefField.longitude =>
    const TextInputType.numberWithOptions(signed: true, decimal: true),
  _ => null,
};

/// A control with the small label the text fields have.
class _LabelledChoice extends StatelessWidget {
  const _LabelledChoice({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [EditorFieldLabel(label), child],
    );
  }
}

class _SecurityPicker extends StatelessWidget {
  const _SecurityPicker({required this.selected, required this.onChanged});

  final NdefWifiSecurity selected;
  final ValueChanged<NdefWifiSecurity> onChanged;

  static const _order = [
    NdefWifiSecurity.wpa2,
    NdefWifiSecurity.wpa3,
    NdefWifiSecurity.open,
  ];

  @override
  Widget build(BuildContext context) {
    String label(NdefWifiSecurity security) => switch (security) {
      NdefWifiSecurity.wpa2 => 'WPA2',
      NdefWifiSecurity.wpa3 => 'WPA3',
      NdefWifiSecurity.open => l10n.ndefWifiOpenShort,
    };
    if (useCupertinoChrome) {
      return AdaptiveSegmentedControl(
        labels: [for (final security in _order) label(security)],
        selectedIndex: _order.indexOf(selected),
        onValueChanged: (index) => onChanged(_order[index]),
      );
    }
    return SegmentedButton<NdefWifiSecurity>(
      segments: [
        for (final security in _order)
          ButtonSegment(value: security, label: Text(label(security))),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
      showSelectedIcon: false,
    );
  }
}
