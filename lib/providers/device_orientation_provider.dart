import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the iOS device's top edge (the side with the NFC antenna) is on
/// the right of the screen, or null outside iOS or before the first reading.
///
/// The scan page glues its tap target to that edge. Safe-area insets do not
/// describe it: iPhones keep symmetric landscape insets, and the Duo's
/// vertical bar makes one side look like the top. UIKit reports the physical
/// side instead.
final iosDeviceTopOnRightProvider =
    NotifierProvider<_IosDeviceTopOnRightNotifier, bool?>(
      _IosDeviceTopOnRightNotifier.new,
    );

class _IosDeviceTopOnRightNotifier extends Notifier<bool?>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('moe.neri.hinatago/device_orientation');

  @override
  bool? build() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }

    _channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    });
    _refresh();
    // The window scene can still be portrait while the first Flutter frame is
    // built, so read again once the launch rotation has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.mounted) _refresh();
    });
    return null;
  }

  @override
  void didChangeMetrics() {
    // Padding changes too, so a 180° turn between the two landscapes (where
    // the size stays the same) still triggers a re-read.
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'deviceTopOnRightChanged') return;
    final value = call.arguments;
    if (value is bool && ref.mounted) state = value;
  }

  Future<void> _refresh() async {
    try {
      final topOnRight = await _channel.invokeMethod<bool>(
        'getDeviceTopOnRight',
      );
      if (ref.mounted) state = topOnRight;
    } on PlatformException {
      if (ref.mounted) state = null;
    } on MissingPluginException {
      if (ref.mounted) state = null;
    }
  }
}
