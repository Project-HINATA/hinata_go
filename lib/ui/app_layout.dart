import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:hinata_go/context_extensions.dart';

const double compactLayoutBreakpoint = 600;
const double expandedRailBreakpoint = 840;
const double compactPhoneExpandedRailBreakpoint = 720;

class AppLayoutInfo {
  const AppLayoutInfo({
    required this.size,
    required this.orientation,
    required this.viewPadding,
    required this.systemGestureInsets,
  });

  factory AppLayoutInfo.fromContext(BuildContext context) {
    final mediaQuery = context.mediaQuery;
    final ui.FlutterView view = context.flutterView;
    // Use the active Flutter view instead of the backing display so rotation
    // follows the actual app viewport on phones and tablets.
    final Size viewportSize = view.physicalSize / view.devicePixelRatio;

    return AppLayoutInfo(
      size: viewportSize,
      orientation: viewportSize.width >= viewportSize.height
          ? Orientation.landscape
          : Orientation.portrait,
      viewPadding: mediaQuery.viewPadding,
      systemGestureInsets: mediaQuery.systemGestureInsets,
    );
  }

  final Size size;
  final Orientation orientation;
  final EdgeInsets viewPadding;
  final EdgeInsets systemGestureInsets;

  double get shortestSide => math.min(size.width, size.height);

  bool get isLandscape => orientation == Orientation.landscape;

  bool get isPhone => shortestSide < compactLayoutBreakpoint;

  bool get isCompactLandscapePhone => isLandscape && isPhone;

  bool get useRailNavigation =>
      isLandscape || size.width >= compactLayoutBreakpoint;

  bool get showPageAppBar => !isLandscape;

  bool get canExtendRail => isCompactLandscapePhone
      ? size.width >= compactPhoneExpandedRailBreakpoint
      : size.width >= expandedRailBreakpoint;

  bool get deviceTopOnRight {
    final leftSignal = viewPadding.left + systemGestureInsets.left;
    final rightSignal = viewPadding.right + systemGestureInsets.right;

    if (leftSignal == rightSignal) {
      return false;
    }

    return rightSignal > leftSignal;
  }

  bool get railOnLeadingSide {
    if (isLandscape && !isPhone) {
      return true;
    }

    return deviceTopOnRight;
  }
}

extension AppLayoutContext on BuildContext {
  AppLayoutInfo get appLayout => AppLayoutInfo.fromContext(this);
}
