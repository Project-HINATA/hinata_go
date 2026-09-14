import 'package:flutter/widgets.dart';

/// Reports whether the surrounding shell branch is the one currently on screen.
///
/// The shell keeps every branch mounted so that its state survives tab switches. A widget inside an
/// inactive branch therefore still sees its own route as current, and has to consult this scope to
/// find out that it is off screen.
class ShellBranchScope extends InheritedWidget {
  const ShellBranchScope({
    super.key,
    required this.isSelected,
    required super.child,
  });

  final bool isSelected;

  /// Returns `null` for widgets that do not live inside a shell branch, such as root-level routes.
  static bool? maybeIsSelected(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShellBranchScope>()
      ?.isSelected;

  @override
  bool updateShouldNotify(ShellBranchScope oldWidget) =>
      isSelected != oldWidget.isSelected;
}
