import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/native_top_bar_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTopBarBridge.channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTopBarBridge.channel, null);
  });

  Widget host({bool iOS26 = true}) {
    return MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AdaptiveToolbarHost(
          nativeTopBar: true,
          debugIOS26: iOS26,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  ToolbarChromeScope scope(WidgetTester tester) =>
      tester.widget<ToolbarChromeScope>(find.byType(ToolbarChromeScope));

  Future<void> sendLayout(Map<String, Object?> layout) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          NativeTopBarBridge.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('layout', layout),
          ),
          (_) {},
        );
  }

  testWidgets('the native bar owns the chrome on iOS 26', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(
      calls.map((call) => call.method),
      containsAll(<String>['reset', 'getLayout']),
    );
    expect(scope(tester).nativeTopBarOwned, isTrue);

    // Before iOS 26 the pages draw their own bars.
    calls.clear();
    await tester.pumpWidget(host(iOS26: false));
    await tester.pump();
    expect(scope(tester).nativeTopBarOwned, isFalse);
    expect(scope(tester).largeTitles, isFalse);
  });

  testWidgets('pages follow the layout the native shell reports', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(scope(tester).largeTitles, isFalse);

    // An iPhone in portrait: large titles under a visible bar.
    await sendLayout({'largeTitles': true, 'titleMargin': 16.0});
    await tester.pump();
    expect(scope(tester).largeTitles, isTrue);
    expect(scope(tester).topBarHidden, isFalse);
    expect(scope(tester).largeTitleMargin, 16);

    // In landscape the shell hides its bar.
    await sendLayout({'barHidden': true});
    await tester.pump();
    expect(scope(tester).largeTitles, isFalse);
    expect(scope(tester).topBarHidden, isTrue);

    // Beside the iPhone Duo vertical bar the tabs run vertically.
    await sendLayout({'verticalTabs': true});
    await tester.pump();
    expect(scope(tester).verticalTabs, isTrue);
    expect(scope(tester).topBarHidden, isFalse);
  });

  testWidgets('switching tabs resets the native stack instead of pushing', (
    tester,
  ) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          builder: (context, child) => AdaptiveToolbarHost(
            nativeTopBar: true,
            debugIOS26: true,
            child: child!,
          ),
          home: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, current, _) => Stack(
              children: [
                for (var i = 0; i < 2; i++)
                  Offstage(
                    offstage: i != current,
                    child: TickerMode(
                      enabled: i == current,
                      child: AdaptiveScaffold(
                        appBar: AdaptiveAppBar(
                          title: i == 0 ? 'Scan' : 'Cards',
                        ),
                        body: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    String? lastResetTitle() {
      for (final call in calls.reversed) {
        if (call.method != 'reset') continue;
        final arguments = call.arguments as Map<Object?, Object?>;
        final item = arguments['item']! as Map<Object?, Object?>;
        return item['title'] as String?;
      }
      return null;
    }

    expect(lastResetTitle(), 'Scan');

    calls.clear();
    index.value = 1;
    await tester.pump();
    await tester.pump();
    expect(lastResetTitle(), 'Cards');
    expect(calls.map((call) => call.method), isNot(contains('push')));
  });

  testWidgets('a page push never marks the bar covered', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => AdaptiveToolbarHost(
            nativeTopBar: true,
            debugIOS26: true,
            child: child!,
          ),
          home: const AdaptiveScaffold(
            appBar: AdaptiveAppBar(title: 'Home'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    calls.clear();

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Detail'),
          body: SizedBox.expand(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final covered = calls
        .where((call) => call.method == 'setCovered')
        .map((call) => (call.arguments as Map<Object?, Object?>)['covered'])
        .toList();
    expect(covered, isNot(contains(true)));
    expect(calls.map((call) => call.method), contains('push'));

    await tester.pumpAndSettle();
    expect(
      calls
          .where((call) => call.method == 'setCovered')
          .map((call) => (call.arguments as Map<Object?, Object?>)['covered']),
      isNot(contains(true)),
    );
  });
}
