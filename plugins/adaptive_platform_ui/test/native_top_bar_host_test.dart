import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/platform/system_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/native_top_bar_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

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

  Widget host({required Size size, EdgeInsets padding = EdgeInsets.zero}) {
    return MediaQuery(
      data: MediaQueryData(size: size, padding: padding, viewPadding: padding),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AdaptiveToolbarHost(
          nativeTopBar: true,
          debugFold: FoldableData.unsupported,
          debugVerticalBarEdge: SystemVerticalBarEdge.unknown,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  bool? lastVisibility() {
    for (final call in calls.reversed) {
      if (call.method == 'setVisible') {
        return (call.arguments as Map<Object?, Object?>)['visible'] as bool?;
      }
    }
    return null;
  }

  testWidgets('the native bar owns the chrome everywhere on iOS', (
    tester,
  ) async {
    await tester.pumpWidget(host(size: const Size(390, 844)));
    await tester.pump();
    expect(
      calls.map((call) => call.method),
      containsAll(<String>['reset', 'setVisible']),
    );
    expect(lastVisibility(), isTrue);
    expect(
      tester
          .widget<ToolbarChromeScope>(find.byType(ToolbarChromeScope))
          .nativeTopBarOwned,
      isTrue,
    );

    // Landscape keeps the native controller active but hides it: pages have
    // no top bar there and must not reserve its strip.
    calls.clear();
    await tester.pumpWidget(host(size: const Size(844, 390)));
    await tester.pump();
    expect(calls.single.method, 'setVisible');
    expect(lastVisibility(), isFalse);

    // A Duo pose keeps the same native controller: UIKit moves the item into
    // the system vertical bar, so the bar stays visible and owned.
    calls.clear();
    await tester.pumpWidget(
      host(
        size: const Size(466, 678),
        padding: const EdgeInsets.only(right: 84, bottom: 34),
      ),
    );
    await tester.pump();
    expect(lastVisibility(), isTrue);
    expect(
      tester
          .widget<ToolbarChromeScope>(find.byType(ToolbarChromeScope))
          .nativeTopBarOwned,
      isTrue,
    );

    // iPad uses the same controller rather than a second Flutter chrome. It
    // was already visible, so the bridge has nothing new to send.
    calls.clear();
    await tester.pumpWidget(host(size: const Size(1024, 1366)));
    await tester.pump();
    expect(lastVisibility(), isNot(false));
    expect(
      tester
          .widget<ToolbarChromeScope>(find.byType(ToolbarChromeScope))
          .nativeTopBarOwned,
      isTrue,
    );

    // Back to an iPhone portrait: still the same active controller, so only
    // its visibility is re-sent.
    calls.clear();
    await tester.pumpWidget(host(size: const Size(390, 844)));
    await tester.pump();
    expect(lastVisibility(), isNot(false));
    expect(calls.map((call) => call.method), isNot(contains('reset')));
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
            debugFold: FoldableData.unsupported,
            debugVerticalBarEdge: SystemVerticalBarEdge.unknown,
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
            debugFold: FoldableData.unsupported,
            debugVerticalBarEdge: SystemVerticalBarEdge.unknown,
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
