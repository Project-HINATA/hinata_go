import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The direction the app's primary navigation bar runs.
///
/// * [Axis.vertical]: a side rail on Material, or the iPhone Duo side bar.
/// * [Axis.horizontal]: a bottom navigation/tab bar.
///
/// Updated from the widget tree once, so the route transition, page chrome
/// and swipe handling all read the same value instead of re-deriving it.
final navigationBarAxisProvider =
    NotifierProvider<NavigationBarAxisNotifier, Axis>(
      NavigationBarAxisNotifier.new,
    );

class NavigationBarAxisNotifier extends Notifier<Axis> {
  @override
  Axis build() => Axis.horizontal;

  void setAxis(Axis axis) {
    if (state != axis) state = axis;
  }
}
