import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/providers/nfc_provider.dart';
import 'package:hinata_go/providers/settings_provider.dart';
import 'package:hinata_go/providers/storage_provider.dart';
import 'package:hinata_go/services/notification_service.dart';
import 'navigation/router.dart'; // Keep this import as it's not explicitly removed or replaced by the instruction

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
            return _SystemUiController(child: child ?? const SizedBox.shrink());
          },
          onGenerateTitle: (context) => context.l10n.appTitle,
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
