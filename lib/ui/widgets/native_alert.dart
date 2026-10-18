import 'package:flutter/widgets.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

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
