import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/providers/app_update_provider.dart';
import 'package:hinata_go/providers/app_update_state.dart';
import 'package:hinata_go/providers/settings_provider.dart';
import 'package:hinata_go/ui/pages/settings_page.dart';

void main() {
  group('AppUpdateState & Version Display Tests', () {
    test('formats version with commit hash correctly', () {
      const stateWithHash = AppUpdateState(
        currentVersion: '2.4.3',
        commitHash: 'e10854fa1b2c',
      );
      expect(stateWithHash.versionDisplay, 'HINATA Go v2.4.3 (e10854f)');

      const stateWithoutHash = AppUpdateState(
        currentVersion: '2.4.3',
        commitHash: '',
      );
      expect(stateWithoutHash.versionDisplay, 'HINATA Go v2.4.3');
    });
  });

  group('SettingsPage UI Tests', () {
    Widget buildTestWidget({
      required AppUpdateState updateState,
      TargetPlatform platform = TargetPlatform.android,
    }) {
      return ProviderScope(
        overrides: [
          appUpdateProvider.overrideWith(() => _MockAppUpdateNotifier(updateState)),
          settingsProvider.overrideWith(() => _MockSettingsNotifier()),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      );
    }

    testWidgets('shows version with commit hash on About item', (tester) async {
      const updateState = AppUpdateState(
        currentVersion: '2.4.3',
        commitHash: 'abcdef123456',
        isUpdateSupported: true,
      );

      await tester.pumpWidget(buildTestWidget(updateState: updateState));
      await tester.pumpAndSettle();

      expect(find.text('HINATA Go v2.4.3 (abcdef1)'), findsOneWidget);
    });

    testWidgets('shows both GitHub and Google Play buttons on Android when update is available', (tester) async {
      const updateState = AppUpdateState(
        currentVersion: '2.4.3',
        latestVersion: '2.5.0',
        hasUpdate: true,
        isUpdateSupported: true,
        downloadUrl: 'https://github.com/nerimoe/hinata_go/releases/tag/v2.5.0',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          buildTestWidget(updateState: updateState, platform: TargetPlatform.android),
        );
        await tester.pumpAndSettle();

        expect(find.text('GitHub Release'), findsOneWidget);
        expect(find.text('Google Play'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shows App Store button on iOS when update is available', (tester) async {
      const updateState = AppUpdateState(
        currentVersion: '2.4.3',
        latestVersion: '2.5.0',
        hasUpdate: true,
        isUpdateSupported: true,
        downloadUrl: 'https://github.com/nerimoe/hinata_go/releases/tag/v2.5.0',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          buildTestWidget(updateState: updateState, platform: TargetPlatform.iOS),
        );
        await tester.pumpAndSettle();

        expect(find.text('App Store'), findsOneWidget);
        expect(find.text('Google Play'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

class _MockAppUpdateNotifier extends AppUpdateNotifier {
  final AppUpdateState _initial;
  _MockAppUpdateNotifier(this._initial);

  @override
  AppUpdateState build() => _initial;
}

class _MockSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
        cardExpirationSeconds: 10,
        language: AppLanguage.system,
      );
}
