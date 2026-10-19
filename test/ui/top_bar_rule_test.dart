import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/ui/widgets/app_scaffold.dart';

/// The iOS chrome decides its layout from platform rules, not from measuring
/// the bar, so the rules are pinned down here without a device.
void main() {
  group('tab transition axis', () {
    test('iPhone slides sideways in portrait and landscape', () {
      for (final useRail in [false, true]) {
        expect(
          tabTransitionAxis(
            usesNativeBar: true,
            duoVerticalBar: false,
            useRail: useRail,
          ),
          Axis.horizontal,
        );
      }
    });

    test('the iPhone Duo vertical bar slides vertically', () {
      expect(
        tabTransitionAxis(
          usesNativeBar: true,
          duoVerticalBar: true,
          useRail: false,
        ),
        Axis.vertical,
      );
    });

    test('Android and web follow the navigation rail', () {
      expect(
        tabTransitionAxis(
          usesNativeBar: false,
          duoVerticalBar: false,
          useRail: false,
        ),
        Axis.horizontal,
      );
      expect(
        tabTransitionAxis(
          usesNativeBar: false,
          duoVerticalBar: false,
          useRail: true,
        ),
        Axis.vertical,
      );
    });
  });

  group('Material top bar', () {
    test('pages beside the rail drop the bar in landscape', () {
      expect(
        shouldShowMaterialTopBar(landscape: true, railHosted: true),
        isFalse,
      );
    });

    test('pushed and standalone pages keep their bar', () {
      expect(
        shouldShowMaterialTopBar(landscape: true, railHosted: false),
        isTrue,
      );
    });

    test('portrait keeps the bar even beside a rail', () {
      expect(
        shouldShowMaterialTopBar(landscape: false, railHosted: true),
        isTrue,
      );
    });
  });

  group('iOS top bar', () {
    test('portrait keeps the bar everywhere', () {
      for (final duo in [false, true]) {
        expect(
          shouldShowIOSTopBar(
            usesNativeBar: true,
            landscape: false,
            duoVerticalBar: duo,
          ),
          isTrue,
        );
      }
    });

    test('landscape drops the bar except on the Duo', () {
      expect(
        shouldShowIOSTopBar(
          usesNativeBar: true,
          landscape: true,
          duoVerticalBar: false,
        ),
        isFalse,
      );
      expect(
        shouldShowIOSTopBar(
          usesNativeBar: true,
          landscape: true,
          duoVerticalBar: true,
        ),
        isTrue,
      );
    });

    test('Material platforms never use the iOS bar', () {
      expect(
        shouldShowIOSTopBar(
          usesNativeBar: false,
          landscape: false,
          duoVerticalBar: false,
        ),
        isFalse,
      );
    });
  });
}
