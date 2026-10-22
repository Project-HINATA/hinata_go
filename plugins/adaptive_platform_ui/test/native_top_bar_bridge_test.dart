import 'package:adaptive_platform_ui/src/toolbar/native_top_bar_bridge.dart';
import 'package:adaptive_platform_ui/src/toolbar/toolbar_blend.dart';
import 'package:adaptive_platform_ui/src/toolbar/toolbar_registry.dart';
import 'package:adaptive_platform_ui/src/toolbar/top_bar_accessory.dart';
import 'package:adaptive_platform_ui/src/widgets/adaptive_app_bar.dart';
import 'package:adaptive_platform_ui/src/widgets/adaptive_app_bar_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> sendNative(String method, Map<String, Object?> arguments) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          NativeTopBarBridge.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  late List<MethodCall> calls;
  late ToolbarRegistry registry;
  late ToolbarBlend blend;
  late NativeTopBarBridge bridge;

  ToolbarEntry entry({
    required String title,
    List<AdaptiveAppBarAction> actions = const <AdaptiveAppBarAction>[],
    NativeToolbarLeading? nativeLeading,
    VoidCallback? onNativeLeadingTap,
    bool logo = false,
  }) {
    return ToolbarEntry(
      id: title,
      appBar: AdaptiveAppBar(
        title: title,
        actions: actions,
        nativeLogo: logo,
        nativeLeading: nativeLeading,
        onNativeLeadingTap: onNativeLeadingTap,
      ),
      route: null,
      navigator: null,
      visible: true,
    );
  }

  Map<String, Object?> itemOf(MethodCall call) {
    final arguments = call.arguments as Map<Object?, Object?>;
    final item = arguments['item']! as Map<Object?, Object?>;
    return item.map((key, value) => MapEntry(key! as String, value));
  }

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTopBarBridge.channel, (call) async {
          calls.add(call);
          return null;
        });
    registry = ToolbarRegistry();
    blend = ToolbarBlend(registry: registry, vsync: const TestVSync());
    bridge = NativeTopBarBridge(blend: blend);
  });

  tearDown(() {
    bridge.dispose();
    blend.dispose();
    registry.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTopBarBridge.channel, null);
  });

  test('mirrors reset, push, update and pop in order', () async {
    bridge.update(active: true);
    await pumpEventQueue();
    expect(
      calls.map((call) => call.method),
      containsAll(<String>['reset', 'getLayout']),
    );
    calls.clear();

    final root = entry(title: 'HINATA Go', logo: true);
    blend.onNativeTransition!(NativeBarTransition.reset(root));
    await pumpEventQueue();
    expect(calls.single.method, 'reset');
    final rootItem = itemOf(calls.single);
    expect(rootItem['title'], 'HINATA Go');
    expect(rootItem['logo'], true);
    expect(rootItem['back'], false);
    expect(rootItem['leading'], isNull);

    calls.clear();
    final logs = entry(
      title: 'Scan History Logs',
      actions: [AdaptiveAppBarAction(iosSymbol: 'trash', onPressed: () {})],
    );
    blend.onNativeTransition!(NativeBarTransition.push(logs));
    await pumpEventQueue();
    expect(calls.single.method, 'push');
    final logsItem = itemOf(calls.single);
    final logsToken = logsItem['token']! as int;
    expect(logsItem['title'], 'Scan History Logs');
    expect(logsItem['back'], false);
    expect((logsItem['actions']! as List<Object?>).single, {
      'icon': 'trash',
      'spacerAfter': 0,
    });

    // An unchanged page does not resend the same item, but its fresh
    // callbacks must still replace the ones the native bar will invoke.
    calls.clear();
    var freshPresses = 0;
    final rebuilt = entry(
      title: 'Scan History Logs',
      actions: [
        AdaptiveAppBarAction(
          iosSymbol: 'trash',
          onPressed: () => freshPresses++,
        ),
      ],
    );
    blend.onNativeTransition!(NativeBarTransition.update(rebuilt));
    await pumpEventQueue();
    expect(calls, isEmpty);
    await sendNative('onAction', {'token': logsToken, 'index': 0});
    expect(freshPresses, 1);

    // A changed page updates the existing placeholder instead of pushing.
    calls.clear();
    final renamed = entry(
      title: 'Scan History Logs',
      actions: [
        AdaptiveAppBarAction(iosSymbol: 'trash', onPressed: () {}),
        AdaptiveAppBarAction(iosSymbol: 'plus', onPressed: () {}),
      ],
    );
    blend.onNativeTransition!(NativeBarTransition.update(renamed));
    await pumpEventQueue();
    expect(calls.single.method, 'update');
    expect((itemOf(calls.single)['actions']! as List<Object?>), hasLength(2));

    calls.clear();
    blend.onNativeTransition!(const NativeBarTransition.pop());
    await pumpEventQueue();
    expect(calls.single.method, 'pop');
    calls.clear();
    blend.onNativeTransition!(const NativeBarTransition.pop());
    await pumpEventQueue();
    expect(calls, isEmpty);

    // A tab switch collapsed the native stack to the page that was on top.
    // Popping it in Flutter must replace that item with the uncovered page.
    blend.onNativeTransition!(NativeBarTransition.reset(logs));
    await pumpEventQueue();
    expect(calls.single.method, 'reset');
    calls.clear();
    blend.onNativeTransition!(NativeBarTransition.popTo(root));
    await pumpEventQueue();
    expect(calls.single.method, 'reset');
    expect(itemOf(calls.single)['title'], 'HINATA Go');
  });

  test('routes native action, leading and back taps by token', () async {
    bridge.update(active: true);
    await pumpEventQueue();
    calls.clear();

    var actions = 0;
    var leading = 0;
    final page = entry(
      title: 'Editor',
      nativeLeading: NativeToolbarLeading.close,
      onNativeLeadingTap: () => leading++,
      actions: [
        AdaptiveAppBarAction(iosSymbol: 'trash', onPressed: () => actions++),
      ],
    );
    blend.onNativeTransition!(NativeBarTransition.reset(page));
    await pumpEventQueue();
    final token = itemOf(calls.single)['token']! as int;
    expect(itemOf(calls.single)['leading'], 'close');

    await sendNative('onAction', {'token': token, 'index': 0});
    await sendNative('onLeading', {'token': token});
    await sendNative('onAction', {'token': token + 99, 'index': 0});
    expect(actions, 1);
    expect(leading, 1);

    calls.clear();
    bridge.update(active: false);
    await pumpEventQueue();
    expect(calls, isEmpty);

    await sendNative('onAction', {'token': token, 'index': 0});
    expect(actions, 1, reason: 'an inactive bridge must ignore native taps');
  });

  test('sends the top page scroll state and its large title', () async {
    bridge.update(active: true);
    await pumpEventQueue();
    calls.clear();

    Map<String, Object?> argumentsOf(MethodCall call) =>
        (call.arguments as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key! as String, value),
        );

    final settingsOffset = ValueNotifier<double>(0);
    addTearDown(settingsOffset.dispose);
    final settings = ToolbarEntry(
      id: 'settings',
      appBar: const AdaptiveAppBar(title: 'Settings', largeTitle: true),
      route: null,
      navigator: null,
      visible: true,
      scrollOffset: settingsOffset,
    );
    blend.onNativeTransition!(NativeBarTransition.reset(settings));
    await pumpEventQueue();
    final reset = calls.single;
    expect(itemOf(reset)['largeTitle'], true);
    expect(itemOf(reset)['largeTitleHeight'], kLargeTitleHeight);
    expect(
      itemOf(reset)['largeTitleCollapseOffset'],
      kLargeTitleCollapseOffset,
    );
    // The page arrives with its scroll position, so the bar never shows the
    // wrong title for a frame.
    expect(argumentsOf(reset)['scroll'], {'offset': 0.0});
    final token = itemOf(reset)['token']! as int;

    calls.clear();
    settingsOffset.value = 4;
    await pumpEventQueue();
    expect(calls.single.method, 'scroll');
    expect(argumentsOf(calls.single), {
      'token': token,
      'offset': 4.0,
      'animated': true,
    });

    // Far down the offset is capped, and nothing more is sent.
    calls.clear();
    settingsOffset.value = 500;
    settingsOffset.value = 900;
    await pumpEventQueue();
    expect(calls, hasLength(1));
    expect(argumentsOf(calls.single)['offset'], 200.0);

    // A pushed page has no large title, and the covered page's scrolling no
    // longer reaches the bar.
    calls.clear();
    blend.onNativeTransition!(
      NativeBarTransition.push(entry(title: 'Scan History Logs')),
    );
    await pumpEventQueue();
    expect(itemOf(calls.single).containsKey('largeTitle'), false);
    expect(argumentsOf(calls.single)['scroll'], {'offset': 0.0});
    calls.clear();
    settingsOffset.value = 0;
    await pumpEventQueue();
    expect(calls, isEmpty);

    // Back on the large-title page, the bar catches up with its position.
    blend.onNativeTransition!(const NativeBarTransition.pop());
    await pumpEventQueue();
    expect(calls.map((call) => call.method), ['pop', 'scroll']);
    expect(argumentsOf(calls.last), {
      'token': token,
      'offset': 0.0,
      'animated': true,
    });

    // Pulling the content down moves the chip strip with the large title.
    calls.clear();
    settingsOffset.value = -30;
    await pumpEventQueue();
    expect(argumentsOf(calls.single)['offset'], -30.0);
  });

  test('follows the layout the native shell reports', () async {
    var layoutCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTopBarBridge.channel, (call) async {
          calls.add(call);
          if (call.method != 'getLayout') return null;
          layoutCalls++;
          return {'largeTitles': true, 'titleMargin': 16.0};
        });
    expect(bridge.layout.value, const NativeBarLayout());

    // Asked for when the bridge becomes active.
    bridge.update(active: true);
    await pumpEventQueue();
    expect(layoutCalls, 1);
    expect(
      bridge.layout.value,
      const NativeBarLayout(largeTitles: true, titleMargin: 16),
    );

    // Pushed by the shell whenever its traits change.
    await sendNative('layout', {
      'largeTitles': false,
      'barHidden': true,
      'verticalTabs': false,
    });
    expect(
      bridge.layout.value,
      const NativeBarLayout(largeTitles: false, barHidden: true),
    );
  });

  test('beside a vertical bar every scroll offset is sent', () async {
    bridge.update(active: true);
    await pumpEventQueue();
    final offset = ValueNotifier<double>(0);
    addTearDown(offset.dispose);
    blend.onNativeTransition!(
      NativeBarTransition.reset(
        ToolbarEntry(
          id: 'settings',
          appBar: const AdaptiveAppBar(title: 'Settings'),
          route: null,
          navigator: null,
          visible: true,
          scrollOffset: offset,
        ),
      ),
    );
    await pumpEventQueue();
    await sendNative('layout', {'verticalTabs': true});

    calls.clear();
    offset.value = 500;
    offset.value = 900;
    await pumpEventQueue();
    expect(
      calls.map((call) => (call.arguments as Map<Object?, Object?>)['offset']),
      [500.0, 900.0],
    );
  });

  test('sends chips to the native strip and routes their taps', () async {
    bridge.update(active: true);
    await pumpEventQueue();
    calls.clear();

    final tapped = <String>[];
    AdaptiveToolbarChip chip(String label, {bool selected = false}) =>
        AdaptiveToolbarChip(
          label: label,
          selected: selected,
          onPressed: () => tapped.add('tap $label'),
          onLongPress: () => tapped.add('hold $label'),
        );
    final cards = ToolbarEntry(
      id: 'cards',
      appBar: AdaptiveAppBar(
        title: 'Saved Cards',
        chips: [chip('Favorites', selected: true), chip('History')],
      ),
      route: null,
      navigator: null,
      visible: true,
    );
    blend.onNativeTransition!(NativeBarTransition.reset(cards));
    await pumpEventQueue();
    final item = itemOf(calls.single);
    expect(item['chips'], [
      {'title': 'Favorites', 'selected': true},
      {'title': 'History', 'selected': false},
    ]);
    final token = item['token']! as int;

    await sendNative('onChip', {'token': token, 'index': 1});
    await sendNative('onChipLongPress', {'token': token, 'index': 0});
    await sendNative('onChip', {'token': token, 'index': 5});
    expect(tapped, ['tap History', 'hold Favorites']);
  });
}
