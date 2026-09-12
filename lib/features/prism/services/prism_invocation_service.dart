import 'package:flutter/foundation.dart';
import 'prism_api.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PrismInvocationService extends ChangeNotifier {
  PrismInvocationService._();

  static final PrismInvocationService instance = PrismInvocationService._();

  static const _channel = MethodChannel('moe.neri.hinatago/prism');

  Uri? pendingOrigin;
  String? _pendingShopCode;
  String? _pendingPublicId;
  bool _initialized = false;

  String? get pendingShopCode => _pendingShopCode;
  String? get pendingPublicId => _pendingPublicId;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'invocation' && call.arguments is String) {
        handleURL(call.arguments as String);
      }
    });
    await _readInitialURL();
  }

  Future<void> _readInitialURL() async {
    try {
      final value = await _channel.invokeMethod<String>('getInitialURL');
      if (value != null) handleURL(value);
    } on MissingPluginException {
      // Desktop platforms do not provide the mobile invocation bridge.
    }
  }

  void handleURL(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return;
    try {
      prismOrigin(value);
    } catch (_) {
      return;
    }
    if (uri.pathSegments.length != 3 || uri.pathSegments.first != 't') {
      return;
    }

    final shopCode = uri.pathSegments[1];
    final publicId = uri.pathSegments[2];
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(shopCode) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(publicId) ||
        shopCode.isEmpty ||
        shopCode.length > 32 ||
        publicId.isEmpty ||
        publicId.length > 80) {
      return;
    }
    pendingOrigin = prismOrigin(value);
    _pendingShopCode = shopCode;
    _pendingPublicId = publicId;
    notifyListeners();
  }

  void clear() {
    if (_pendingShopCode == null && _pendingPublicId == null) return;
    pendingOrigin = null;
    _pendingShopCode = null;
    _pendingPublicId = null;
    notifyListeners();
  }
}

final prismInvocationProvider = Provider<PrismInvocationService>((ref) {
  return PrismInvocationService.instance;
});
