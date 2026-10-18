import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'app_scaffold.dart';

import '../../l10n/l10n.dart';

/// One button of a [showNativeAlert].
class NativeAlertChoice<T> {
  const NativeAlertChoice({
    required this.label,
    required this.value,
    this.style = AlertActionStyle.defaultAction,
  });

  final String label;
  final T value;
  final AlertActionStyle style;
}

/// Shows a native iOS alert (Liquid Glass on iOS 26+) with a Cancel button and
/// [choices]. Returns the value of the chosen button, or null when cancelled.
Future<T?> showNativeAlert<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<NativeAlertChoice<T>> choices,
}) async {
  T? result;
  await AdaptiveAlertDialog.show(
    context: context,
    title: title,
    message: message,
    actions: [
      AlertAction(
        title: l10n.cancel,
        style: AlertActionStyle.cancel,
        onPressed: () {},
      ),
      for (final choice in choices)
        AlertAction(
          title: choice.label,
          style: choice.style,
          onPressed: () => result = choice.value,
        ),
    ],
  );
  return result;
}

/// Asks a yes/no question with a native iOS alert; true when confirmed.
Future<bool> showNativeConfirmation(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showNativeAlert<bool>(
    context,
    title: title,
    message: message,
    choices: [
      NativeAlertChoice(
        label: confirmLabel,
        value: true,
        style: destructive
            ? AlertActionStyle.destructive
            : AlertActionStyle.primary,
      ),
    ],
  );
  return confirmed ?? false;
}

/// Asks for one line of text with a native iOS alert; null when cancelled.
Future<String?> showNativeTextInput(
  BuildContext context, {
  required String title,
  required String placeholder,
  String? initialValue,
  required String confirmLabel,
}) {
  return AdaptiveAlertDialog.inputShow(
    context: context,
    title: title,
    input: AdaptiveAlertDialogInput(
      placeholder: placeholder,
      initialValue: initialValue,
    ),
    actions: [
      AlertAction(
        title: l10n.cancel,
        style: AlertActionStyle.cancel,
        onPressed: () {},
      ),
      AlertAction(
        title: confirmLabel,
        style: AlertActionStyle.primary,
        onPressed: () {},
      ),
    ],
  );
}

/// A labelled choice in a [NativeChoiceField].
class NativeChoice<T> {
  const NativeChoice({required this.label, required this.value});

  final String label;
  final T value;
}

/// A form field that picks one value from the native iOS menu, or a Material
/// dropdown elsewhere.
///
/// Dropdowns from the Material library open a Flutter overlay that can end up
/// under the fixed iOS toolbar; a native menu is presented by UIKit above
/// everything, so it never collides with the bar.
class NativeChoiceField<T> extends StatelessWidget {
  const NativeChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<NativeChoice<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!useCupertinoChrome) {
      return DropdownButtonFormField<T>(
        isExpanded: true,
        initialValue: selected,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.label)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      );
    }

    return _NativeChoiceRow<T>(
      label: label,
      options: options,
      selected: selected,
      onChanged: onChanged,
    );
  }
}

/// The iOS rendering of [NativeChoiceField]: the field's label above a row
/// that opens the native menu and shows the current choice. The whole row is
/// the menu button, so it is as easy to hit as the Material dropdown it
/// replaces.
class _NativeChoiceRow<T> extends StatelessWidget {
  const _NativeChoiceRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<NativeChoice<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = options
        .where((option) => option.value == selected)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        AdaptivePopupMenuButton.widget<T>(
          items: [
            for (final option in options)
              AdaptivePopupMenuItem<T>(
                label: option.label,
                value: option.value,
                selected: option.value == selected,
              ),
          ],
          onSelected: (index, item) {
            final value = item.value;
            if (value is T) onChanged(value);
          },
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
