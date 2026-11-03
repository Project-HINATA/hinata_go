import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import '../../../l10n/l10n.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/native_alert.dart';

/// A page of the NDEF editor: its sections scroll under the bar, with the
/// page's main button floating below them, as on the card detail.
class EditorPage extends StatelessWidget {
  const EditorPage({
    super.key,
    required this.title,
    required this.children,
    required this.button,
    this.closes = false,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final Widget button;

  /// Whether the page opens on its own and is left with a close button,
  /// rather than going back to the page below it.
  final bool closes;
  final List<AdaptiveAppBarAction> actions;

  static const double _buttonHeight = 56;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.padding.bottom > 0 ? media.padding.bottom : 16.0;
    void close() => Navigator.of(context).maybePop();
    return AppScaffold(
      title: title,
      actions: actions,
      nativeLeading: closes ? NativeToolbarLeading.close : null,
      onNativeLeadingTap: closes ? close : null,
      leading: !closes
          ? null
          : useCupertinoChrome
          // A full-size round glass control, like the close and back buttons
          // the system puts in the toolbar.
          ? SizedBox.square(
              dimension: 48,
              child: AdaptiveButton.sfSymbol(
                onPressed: close,
                sfSymbol: const SFSymbol('xmark', size: 20),
                size: AdaptiveButtonSize.large,
                useSmoothRectangleBorder: false,
              ),
            )
          : IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              onPressed: close,
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  20,
                  20 + media.padding.top,
                  20,
                  bottom + _buttonHeight + 32,
                ),
                children: [
                  for (final child in children)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: child,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: bottom,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SizedBox(height: _buttonHeight, child: button),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's main button: a prominent Liquid Glass pill on iOS, a filled
/// button elsewhere, like the card detail's actions.
class EditorPrimaryButton extends StatelessWidget {
  const EditorPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (useCupertinoChrome) {
      return AdaptiveButton.child(
        onPressed: onPressed,
        style: AdaptiveButtonStyle.prominentGlass,
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: false,
        color: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: scheme.onPrimary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// A rounded section, styled as the sections of the card detail.
class EditorSection extends StatelessWidget {
  const EditorSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// An icon in a tinted circle, as the card detail marks its rows.
class EditorIconBadge extends StatelessWidget {
  const EditorIconBadge({super.key, required this.icon, this.size = 18});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(size * 0.45),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size, color: colors.primary),
    );
  }
}

/// A section's title row: its icon, its name and a value in a pill.
class EditorSectionHeader extends StatelessWidget {
  const EditorSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.pill,
  });

  final IconData icon;
  final String title;
  final String? pill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (pill != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                pill!,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled text field, filled like the app's choice rows.
class EditorTextField extends StatelessWidget {
  const EditorTextField({
    super.key,
    required this.controller,
    required this.label,
    this.placeholder,
    this.helper,
    this.error,
    this.multiline = false,
    this.monospace = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? placeholder;
  final String? helper;
  final String? error;
  final bool multiline;
  final bool monospace;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    OutlineInputBorder border(Color color, [double width = 0]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: width == 0
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorFieldLabel(label),
        TextField(
          controller: controller,
          keyboardType: multiline ? TextInputType.multiline : keyboardType,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          autocorrect: !monospace,
          enableSuggestions: !monospace,
          textCapitalization: monospace
              ? TextCapitalization.characters
              : TextCapitalization.none,
          style: monospace
              ? const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Menlo', 'Courier'],
                )
              : null,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: border(colors.outline),
            enabledBorder: border(colors.outline),
            focusedBorder: border(colors.primary, 1.5),
            errorBorder: border(colors.error, 1),
            focusedErrorBorder: border(colors.error, 1.5),
            errorText: error,
            errorMaxLines: 3,
            helperText: error == null ? helper : null,
            helperMaxLines: 4,
          ),
        ),
      ],
    );
  }
}

/// The small label above a field.
class EditorFieldLabel extends StatelessWidget {
  const EditorFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A short note under a form, with an info icon.
class EditorNote extends StatelessWidget {
  const EditorNote(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A value picked from a menu, shown at the end of a row: the native menu on
/// iOS, a Material popup menu elsewhere.
class EditorMenuChoice<T> extends StatelessWidget {
  const EditorMenuChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<NativeChoice<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = options.where((o) => o.value == selected).firstOrNull;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            current?.label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.unfold_more, size: 18, color: colors.primary),
      ],
    );
    if (useCupertinoChrome) {
      return AdaptivePopupMenuButton.widget<T>(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: label,
        ),
      );
    }
    return PopupMenuButton<T>(
      initialValue: selected,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(value: option.value, child: Text(option.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: label,
      ),
    );
  }
}

/// A row in a section: a label with a control at its end.
class EditorChoiceRow extends StatelessWidget {
  const EditorChoiceRow({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const SizedBox(width: 12),
            // The control takes what it needs, up to half the row, and the
            // label the rest.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks whether to leave a page without saving; true to leave.
Future<bool> confirmDiscard(BuildContext context) async {
  if (useCupertinoChrome) {
    return showNativeConfirmation(
      context,
      title: l10n.ndefDiscardTitle,
      message: l10n.ndefDiscardMessage,
      confirmLabel: l10n.ndefDiscard,
      destructive: true,
    );
  }
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.ndefDiscardTitle),
      content: Text(l10n.ndefDiscardMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            l10n.ndefDiscard,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Keeps a page with unsaved changes from closing without asking first.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await confirmDiscard(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
