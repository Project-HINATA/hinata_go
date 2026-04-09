import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final androidDisplayRotationProvider =
    NotifierProvider<_AndroidDisplayRotationNotifier, int?>(
      _AndroidDisplayRotationNotifier.new,
    );

class _AndroidDisplayRotationNotifier extends Notifier<int?>
    with WidgetsBindingObserver {
  static const _displayRotationChannel = MethodChannel(
    'moe.neri.hinatago/display_rotation',
  );

  @override
  int? build() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
    });
    _refreshRotation();
    return null;
  }

  @override
  void didChangeMetrics() {
    _refreshRotation();
  }

  Future<void> _refreshRotation() async {
    try {
      final rotation = await _displayRotationChannel.invokeMethod<int>(
        'getDisplayRotation',
      );
      if (ref.mounted) {
        state = rotation;
      }
    } on PlatformException {
      if (ref.mounted) {
        state = null;
      }
    } on MissingPluginException {
      if (ref.mounted) {
        state = null;
      }
    }
  }
}
