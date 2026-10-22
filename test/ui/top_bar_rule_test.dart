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
            verticalTabs: false,
            useRail: useRail,
          ),
          Axis.horizontal,
        );
      }
    });

    test('tabs in a vertical bar (iPhone Duo) slide vertically', () {
      expect(
        tabTransitionAxis(
          usesNativeBar: true,
          verticalTabs: true,
          useRail: false,
        ),
        Axis.vertical,
      );
    });

    test('Android and web follow the navigation rail', () {
      expect(
        tabTransitionAxis(
          usesNativeBar: false,
          verticalTabs: false,
          useRail: false,
        ),
        Axis.horizontal,
      );
      expect(
        tabTransitionAxis(
          usesNativeBar: false,
          verticalTabs: false,
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
    test('the bar shows unless the native shell hides it', () {
      expect(
        shouldShowIOSTopBar(usesNativeBar: true, topBarHidden: false),
        isTrue,
      );
      expect(
        shouldShowIOSTopBar(usesNativeBar: true, topBarHidden: true),
        isFalse,
      );
    });

    test('Material platforms never use the iOS bar', () {
      expect(
        shouldShowIOSTopBar(usesNativeBar: false, topBarHidden: false),
        isFalse,
      );
    });
  });
}
