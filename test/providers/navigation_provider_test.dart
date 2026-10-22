import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/navigation_provider.dart';

class _NoUpdate extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState();
}

void main() {
  tearDown(() => L10nHolder.update(lookupAppLocalizations(const Locale('zh'))));

  test('tab labels follow the current language without recomputing', () {
    final container = ProviderContainer(
      overrides: [appUpdateProvider.overrideWith(_NoUpdate.new)],
    );
    addTearDown(container.dispose);

    L10nHolder.update(lookupAppLocalizations(const Locale('en')));
    final tabs = container.read(navigationTabsProvider);
    expect(tabs.map((tab) => tab.label), ['Scan', 'Cards', 'Settings']);

    final chinese = lookupAppLocalizations(const Locale('zh'));
    L10nHolder.update(chinese);
    expect(tabs.map((tab) => tab.label), [
      chinese.scan,
      chinese.cards,
      chinese.settings,
    ]);
  });
}
