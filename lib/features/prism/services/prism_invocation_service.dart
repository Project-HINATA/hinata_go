import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PrismInvocationService extends ChangeNotifier {
  PrismInvocationService._();

  static final PrismInvocationService instance = PrismInvocationService._();

  static const _channel = MethodChannel('moe.neri.hinatago/prism');

  String? _pendingShopCode;
  String? _pendingPublicId;
  bool _initialized = false;

  String? get pendingShopCode => _pendingShopCode;
  String? get pendingPublicId => _pendingPublicId;

  void initialize() {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'invocation' && call.arguments is String) {
        handleURL(call.arguments as String);
      }
    });
  }

  void handleURL(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return;
    if (uri.host.toLowerCase() != 'link.neri.moe') return;
    if (uri.pathSegments.length != 3 || uri.pathSegments.first != 't') {
      return;
    }

    final shopCode = uri.pathSegments[1];
    final publicId = uri.pathSegments[2];
    if (shopCode.isEmpty ||
        shopCode.length > 32 ||
        publicId.isEmpty ||
        publicId.length > 80) {
      return;
    }
    _pendingShopCode = shopCode;
    _pendingPublicId = publicId;
    notifyListeners();
  }

  void clear() {
    if (_pendingShopCode == null && _pendingPublicId == null) return;
    _pendingShopCode = null;
    _pendingPublicId = null;
    notifyListeners();
  }
}

final prismInvocationProvider = Provider<PrismInvocationService>((ref) {
  return PrismInvocationService.instance;
});
