import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/providers/settings_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/services/notification_service.dart';
import 'navigation/router.dart';
import 'core/app_host_mode.dart';
import 'ui/widgets/navigation_bar_axis_scope.dart';

Future<void> main() => _bootstrap(AppHostMode.flutterShell);

@pragma('vm:entry-point')
Future<void> nativeMain() => _bootstrap(AppHostMode.nativeIOS);

Future<void> _bootstrap(AppHostMode hostMode) async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        appHostModeProvider.overrideWithValue(hostMode),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    final hostMode = ref.watch(appHostModeProvider);
    ref.listen(nfcProvider, (previous, next) {});

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
          darkScheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          );
        }

        final notificationService = ref.watch(notificationServiceProvider);

        return MaterialApp.router(
          builder: (context, child) {
            L10nHolder.update(AppLocalizations.of(context));
            return _LocaleRefresh(
              child: _SystemUiController(
                // Keeps one Liquid Glass toolbar above the navigator on iOS 26+,
                // and lays it out in the iPhone Duo vertical bar. The toast layer
                // sits above it, so in-app notices are never tucked behind the bar.
                child: Overlay(
                  key: notificationService.overlayKey,
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => AdaptiveToolbarHost(
                        // The native shell's UIKit bars own the top bar.
                        nativeTopBar: hostMode == AppHostMode.nativeIOS,
                        child: NavigationBarAxisScope(
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          onGenerateTitle: (context) => l10n.appTitle,
          scaffoldMessengerKey: notificationService.messengerKey,
          theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
          themeMode: ThemeMode.system,
          locale: settings.language.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        );
      },
    );
  }
}

/// Rebuilds the whole app once the language changes.
///
/// Pages read their strings from the global [l10n], which no widget depends
/// on, so pages that do not rebuild by themselves (tabs kept alive off screen,
/// pages under a pushed route) would keep the previous language, and so would
/// the native bars they publish their titles to.
class _LocaleRefresh extends StatefulWidget {
  const _LocaleRefresh({required this.child});

  final Widget child;

  @override
  State<_LocaleRefresh> createState() => _LocaleRefreshState();
}

class _LocaleRefreshState extends State<_LocaleRefresh> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_locale != null && locale != _locale) {
      // Marked after this frame: dirtying elements mid-build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildDescendants();
      });
    }
    _locale = locale;
  }

  void _rebuildDescendants() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SystemUiController extends StatefulWidget {
  final Widget child;

  const _SystemUiController({required this.child});

  @override
  State<_SystemUiController> createState() => _SystemUiControllerState();
}

class _SystemUiControllerState extends State<_SystemUiController> {
  bool? _isImmersiveModeEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSystemUi();
  }

  @override
  void dispose() {
    _restoreSystemUi();
    super.dispose();
  }

  void _syncSystemUi() {
    final orientation = MediaQuery.orientationOf(context);
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final shouldEnableImmersiveMode =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        orientation == Orientation.landscape &&
        shortestSide < 600;

    if (_isImmersiveModeEnabled == shouldEnableImmersiveMode) {
      return;
    }

    _isImmersiveModeEnabled = shouldEnableImmersiveMode;

    if (shouldEnableImmersiveMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }

    _restoreSystemUi();
  }

  void _restoreSystemUi() {
    _isImmersiveModeEnabled = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
