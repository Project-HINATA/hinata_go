import 'package:adaptive_platform_ui/src/toolbar/native_top_bar_bridge.dart';
import 'package:adaptive_platform_ui/src/toolbar/toolbar_blend.dart';
import 'package:adaptive_platform_ui/src/toolbar/toolbar_registry.dart';
import 'package:adaptive_platform_ui/src/widgets/adaptive_app_bar.dart';
import 'package:adaptive_platform_ui/src/widgets/adaptive_app_bar_action.dart';
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
    bridge.update(active: true, visible: true);
    await pumpEventQueue();
    expect(
      calls.map((call) => call.method),
      containsAll(<String>['reset', 'setVisible']),
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
    bridge.update(active: true, visible: true);
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
    bridge.update(active: false, visible: false);
    await pumpEventQueue();
    expect(calls.single.method, 'setVisible');
    expect((calls.single.arguments as Map<Object?, Object?>)['visible'], false);

    await sendNative('onAction', {'token': token, 'index': 0});
    expect(actions, 1, reason: 'an inactive bridge must ignore native taps');
  });
}
