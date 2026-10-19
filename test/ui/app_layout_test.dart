import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/ui/app_layout.dart';

const _landscapePhone = AppLayoutInfo(
  size: Size(844, 390),
  orientation: Orientation.landscape,
  viewPadding: EdgeInsets.zero,
  systemGestureInsets: EdgeInsets.zero,
);

const _portraitPhone = AppLayoutInfo(
  size: Size(390, 844),
  orientation: Orientation.portrait,
  viewPadding: EdgeInsets.zero,
  systemGestureInsets: EdgeInsets.zero,
);

const _rightLeaningInsets = AppLayoutInfo(
  size: Size(844, 390),
  orientation: Orientation.landscape,
  viewPadding: EdgeInsets.only(right: 44),
  systemGestureInsets: EdgeInsets.zero,
);

const _landscapeTablet = AppLayoutInfo(
  size: Size(1200, 800),
  orientation: Orientation.landscape,
  viewPadding: EdgeInsets.zero,
  systemGestureInsets: EdgeInsets.zero,
);

void main() {
  group('resolveDeviceTopOnRight', () {
    test('follows the Android display rotation in landscape', () {
      expect(
        _landscapePhone.resolveDeviceTopOnRight(
          androidDisplayRotation: 1,
          iosDeviceTopOnRight: null,
        ),
        isFalse,
      );
      expect(
        _landscapePhone.resolveDeviceTopOnRight(
          androidDisplayRotation: 3,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
    });

    test('uses the physical side UIKit reports on iOS', () {
      expect(
        _landscapePhone.resolveDeviceTopOnRight(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: true,
        ),
        isTrue,
      );
      expect(
        _landscapePhone.resolveDeviceTopOnRight(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: false,
        ),
        isFalse,
      );
    });

    test('prefers the platform reading over safe-area insets', () {
      // The insets alone would say right.
      expect(
        _rightLeaningInsets.resolveDeviceTopOnRight(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: false,
        ),
        isFalse,
      );
    });

    test('has no side in portrait', () {
      expect(
        _portraitPhone.resolveDeviceTopOnRight(
          androidDisplayRotation: 2,
          iosDeviceTopOnRight: true,
        ),
        isFalse,
      );
    });

    test('keeps machines without NFC on the left', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        _rightLeaningInsets.resolveDeviceTopOnRight(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: null,
        ),
        isFalse,
      );
    });

    test('falls back to insets on a phone before a reading arrives', () {
      expect(
        _rightLeaningInsets.resolveDeviceTopOnRight(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
    });
  });

  group('resolveRailOnLeadingSide', () {
    test('sits opposite the scan target on a compact phone', () {
      // Target on the right, rail on the left.
      expect(
        _landscapePhone.resolveRailOnLeadingSide(
          androidDisplayRotation: 3,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
      // Target on the left, rail on the right.
      expect(
        _landscapePhone.resolveRailOnLeadingSide(
          androidDisplayRotation: 1,
          iosDeviceTopOnRight: null,
        ),
        isFalse,
      );
    });

    test('keeps a wide tablet rail leading whatever the scan side', () {
      expect(
        _landscapeTablet.resolveRailOnLeadingSide(
          androidDisplayRotation: 1,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
    });

    test('keeps web and desktop rail leading', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        _landscapePhone.resolveRailOnLeadingSide(
          androidDisplayRotation: 1,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
    });

    test('stays leading in portrait', () {
      expect(
        _portraitPhone.resolveRailOnLeadingSide(
          androidDisplayRotation: null,
          iosDeviceTopOnRight: null,
        ),
        isTrue,
      );
    });
  });
}
