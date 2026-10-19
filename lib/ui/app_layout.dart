import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

  bool get canExtendRail => isCompactLandscapePhone
      ? size.width >= compactPhoneExpandedRailBreakpoint
      : size.width >= expandedRailBreakpoint;

  bool get _insetDerivedDeviceTopOnRight {
    final leftSignal = viewPadding.left + systemGestureInsets.left;
    final rightSignal = viewPadding.right + systemGestureInsets.right;

    if (leftSignal == rightSignal) {
      return false;
    }

    return rightSignal > leftSignal;
  }

  /// Whether the device's top edge (where most phones put the NFC antenna)
  /// points to the right of the screen.
  ///
  /// The side only exists in landscape; portrait pages keep the scan target
  /// along the top edge, which is also what an upside-down foldable gets
  /// instead of a target in the bottom-left corner.
  bool resolveDeviceTopOnRight({
    required int? androidDisplayRotation,
    required bool? iosDeviceTopOnRight,
  }) {
    if (!isLandscape) {
      return false;
    }

    if (androidDisplayRotation != null) {
      // On portrait-native phones, Surface.ROTATION_270 corresponds to
      // reverse-landscape, meaning the device top points to the right.
      return androidDisplayRotation == 3;
    }

    if (iosDeviceTopOnRight != null) {
      return iosDeviceTopOnRight;
    }

    // Web and desktop machines have no NFC reader; keep them on the left.
    if (!_hasNfcSensor) {
      return false;
    }

    // Until a platform reading arrives, safe-area insets are the best hint.
    return _insetDerivedDeviceTopOnRight;
  }

  /// The Flutter rail keeps its conventional leading position. Only a phone,
  /// or a book-style foldable whose unfolded window is nearly square, anchors
  /// the scan target to a physical edge; there the rail takes the other edge.
  ///
  /// This is a purely responsive test: the fold itself is never inspected.
  /// A foldable's inner display lands well under 1.25 in landscape, while a
  /// 4:3 tablet starts at 1.33 and desktops are wider.
  bool resolveRailOnLeadingSide({
    required int? androidDisplayRotation,
    required bool? iosDeviceTopOnRight,
  }) {
    if (!isLandscape || !_isHandheldNfcLayout) {
      return true;
    }

    return resolveDeviceTopOnRight(
      androidDisplayRotation: androidDisplayRotation,
      iosDeviceTopOnRight: iosDeviceTopOnRight,
    );
  }

  bool get _isHandheldNfcLayout {
    if (!_hasNfcSensor) {
      return false;
    }

    if (isPhone) {
      return true;
    }

    return isLandscape && size.longestSide / size.shortestSide <= 1.25;
  }

  static bool get _hasNfcSensor =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

extension AppLayoutContext on BuildContext {
  AppLayoutInfo get appLayout => AppLayoutInfo.fromContext(this);
}

/// Marks the pages hosted beside the navigation rail.
///
/// Shared page chrome uses this instead of guessing from route state: only a
/// page that actually sits next to the rail lets the rail take over its top
/// bar in landscape. Pushed routes and standalone pages keep their own bar.
class RailHostScope extends InheritedWidget {
  const RailHostScope({required super.child, super.key});

  static bool isHosted(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RailHostScope>() != null;
  }

  @override
  bool updateShouldNotify(RailHostScope oldWidget) => false;
}
