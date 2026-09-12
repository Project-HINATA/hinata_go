import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/arcadelink_api.dart';
import '../services/arcadelink_native_service.dart';

typedef PrismRequest =
    Future<Map<String, dynamic>> Function(
      String path, {
      Map<String, dynamic>? body,
      bool requireLocation,
    });
final prismRequestProvider = Provider<PrismRequest>((ref) {
  final api = ArcadeLinkAPI();
  ref.onDispose(api.dispose);
  final native = ArcadeLinkNativeService();
  return (path, {body, requireLocation = false}) =>
      ArcadeLinkNativeService.isAvailable
      ? native.request(path, body: body, requireLocation: requireLocation)
      : api.request(path, body: body, requireLocation: requireLocation);
});
final prismVisitProvider =
    NotifierProvider.autoDispose<PrismVisitController, PrismVisit>(
      PrismVisitController.new,
    );

// These JSON values are the existing shop/pricing/settlement API documents.
// Keep their full details for the native receipt instead of recomputing charges.
class PrismVisit {
  const PrismVisit({
    this.shop,
    this.summary,
    this.assets = const [],
    this.history = const [],
    this.user,
    this.coinUsed = false,
    this.mahjong,
    this.preview,
    this.binding,
    this.password,
    this.gate = 'loading',
    this.power = 'unmanaged',
    this.busy = false,
    this.error,
    this.notice,
  });
  final Map<String, dynamic>? shop, summary, preview, binding, password, user;
  final Map<String, dynamic>? mahjong;
  final List<Map<String, dynamic>> assets, history;
  final String gate, power;
  final bool busy, coinUsed;
  final Object? error;
  final String? notice;
  bool get billing => shop?['shop']['billingEnabled'] == true;
  bool get member => shop?['membership'] != null;
  bool get active => summary?['activeSession'] != null;
  bool geo(String key) =>
      (shop?['shop']['locationEnabled'] ?? shop?['shop'][key]) == true;
  PrismVisit copy({
    Map<String, dynamic>? shop,
    Map<String, dynamic>? summary,
    List<Map<String, dynamic>>? assets,
    List<Map<String, dynamic>>? history,
    Map<String, dynamic>? user,
    bool? coinUsed,
    Map<String, dynamic>? mahjong,
    Map<String, dynamic>? preview,
    Map<String, dynamic>? binding,
    Map<String, dynamic>? password,
    String? gate,
    String? power,
    bool? busy,
    Object? error,
    String? notice,
    bool clearPreview = false,
  }) => PrismVisit(
    shop: shop ?? this.shop,
    summary: summary ?? this.summary,
    assets: assets ?? this.assets,
    history: history ?? this.history,
    user: user ?? this.user,
    coinUsed: coinUsed ?? this.coinUsed,
    mahjong: mahjong ?? this.mahjong,
    preview: clearPreview ? null : preview ?? this.preview,
    binding: binding ?? this.binding,
    password: password ?? this.password,
    gate: gate ?? this.gate,
    power: power ?? this.power,
    busy: busy ?? this.busy,
    error: error,
    notice: notice ?? this.notice,
  );
}

class PrismVisitController extends Notifier<PrismVisit> {
  late String shopCode;
  late ArcadeLinkMachineSession session;
  String _userId = '';
  int _version = 0;
  Timer? _timer;
  int _refreshRevision = 0;
  bool ticketConsumed = false;
  @override
  PrismVisit build() {
    ref.onDispose(() {
      _version++;
      _timer?.cancel();
    });
    return const PrismVisit();
  }

  String path([String suffix = '']) =>
      '/api/v1/shops/${Uri.encodeComponent(shopCode)}${suffix.isEmpty ? '' : '/$suffix'}';
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool requireLocation = false,
  }) async {
    final version = _version;
    final result = await ref.read(prismRequestProvider)(
      path,
      body: body,
      requireLocation: requireLocation,
    );
    if (!ref.mounted || version != _version) throw StateError('Visit changed');
    return result;
  }

  Future<void> load(String code, ArcadeLinkMachineSession value) async {
    _version++;
    _timer?.cancel();
    shopCode = code;
    session = value;
    ticketConsumed = false;
    state = const PrismVisit();
    await refresh();
  }

  void clear() {
    _version++;
    _refreshRevision++;
    _timer?.cancel();
    _userId = '';
    state = const PrismVisit();
  }

  static bool _expired(Object error) =>
      (error is ArcadeLinkException && error.code == 'TICKET_EXPIRED') ||
      (error is PlatformException && error.code == 'TICKET_EXPIRED');

  Future<void> refresh() async {
    final revision = ++_refreshRevision;
    _timer?.cancel();
    final version = _version;
    try {
      final shop = await request(path());
      final me = await request('/api/v1/me');
      final userId = (me['user'] as Map<String, dynamic>?)?['id'] as String?;
      if (userId == null) {
        throw const ArcadeLinkException(
          '请先登录',
          code: 'AUTHENTICATION_REQUIRED',
        );
      }
      var device = <String, dynamic>{'gate': state.gate, 'power': state.power};
      if (!ticketConsumed) {
        try {
          device = await request(
            '/api/v1/devices/session/state?ticket=${Uri.encodeComponent(session.ticket)}',
          );
        } catch (error) {
          if (!_expired(error)) rethrow;
          expire();
          device = {'gate': 'expired', 'power': state.power};
        }
      }
      Map<String, dynamic>? summary;
      List<Map<String, dynamic>> assets = [], history = [];
      if (shop['membership'] != null &&
          shop['shop']['billingEnabled'] == true) {
        summary = await request(path('player/me'));
        assets = _rows((await request(path('player/assets')))['holdings']);
        history = _rows(
          (await request(path('player/sessions/history')))['sessions'],
        );
      }
      if (!ref.mounted || version != _version || revision != _refreshRevision) {
        return;
      }
      _userId = userId;
      state = state.copy(
        shop: shop,
        summary: summary,
        assets: assets,
        history: history,
        user: me['user'] as Map<String, dynamic>?,
        coinUsed: device['coinUsed'] == true || state.coinUsed,
        mahjong: device['mahjong'] as Map<String, dynamic>?,
        gate: device['gate'] as String,
        power: device['power'] as String,
      );
      _timer?.cancel();
      if (state.gate == 'qq' &&
          (state.binding == null ||
              DateTime.parse(
                state.binding!['expiresAt'] as String,
              ).isBefore(DateTime.now()))) {
        final binding = await request(path('qq-binding'), body: {});
        if (revision != _refreshRevision) return;
        state = state.copy(binding: binding);
      }
      if (!ticketConsumed &&
          (state.gate == 'qq' ||
              state.power == 'off' ||
              session.machine.has('mahjong'))) {
        _timer = Timer(const Duration(seconds: 3), () {
          if (!state.busy) {
            unawaited(refresh());
          }
        });
      }
    } catch (error) {
      if (ref.mounted && version == _version && revision == _refreshRevision) {
        state = state.copy(error: error);
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (state.busy) return;
    final version = _version;
    _refreshRevision++;
    _timer?.cancel();
    state = state.copy(busy: true);
    try {
      await action();
    } catch (error) {
      if (ref.mounted && version == _version) {
        final code = error is ArcadeLinkException
            ? error.code
            : error is PlatformException
            ? error.code
            : null;
        if (_expired(error) ||
            ['DEVICE_RESULT_UNKNOWN', 'OPERATION_PENDING'].contains(code)) {
          expire();
        } else if (code == 'COIN_ALREADY_USED') {
          state = state.copy(coinUsed: true);
        } else {
          state = state.copy(error: error);
        }
      }
    } finally {
      if (ref.mounted && version == _version) {
        state = state.copy(busy: false, error: state.error);
      }
    }
  }

  void expire() {
    ticketConsumed = true;
    _timer?.cancel();
    state = state.copy(gate: 'expired');
  }

  Future<Map<String, dynamic>> pricingDate(String date) async =>
      request('${path()}?date=$date');

  Future<void> bindQQ() => _act(() async {
    final binding = await request(path('qq-binding'), body: {});
    state = state.copy(binding: binding);
    await refresh();
  });
  Future<Map<String, dynamic>> operation(
    String key,
    String endpoint,
    Map<String, dynamic> body,
    bool geo,
  ) async {
    final version = _version;
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted || version != _version) throw StateError('Visit changed');
    final storageKey = 'prism.operation.$_userId.$shopCode.$key';
    final saved = prefs.getString(storageKey);
    if (saved != null && key.startsWith('device.')) {
      throw const ArcadeLinkException(
        '操作结果待确认，请联系店员，不要重复操作',
        code: 'OPERATION_PENDING',
      );
    }
    final payload = saved == null
        ? {...body, 'operationId': const Uuid().v4()}
        : jsonDecode(saved) as Map<String, dynamic>;
    if (saved == null &&
        !await prefs.setString(storageKey, jsonEncode(payload))) {
      throw StateError('Unable to persist operation');
    }
    try {
      final response = await request(
        endpoint,
        body: payload,
        requireLocation: geo,
      );
      await prefs.remove(storageKey);
      if (!ref.mounted || version != _version) {
        throw StateError('Visit changed');
      }
      return response;
    } catch (error) {
      final code = error is ArcadeLinkException
          ? error.code
          : error is PlatformException
          ? error.code
          : null;
      final nativeStatus = error is PlatformException && error.details is Map
          ? (error.details as Map)['statusCode'] as int?
          : null;
      final localLocationFailure = [
        'location_denied',
        'location_unavailable',
        'location_timeout',
      ].contains(code);
      final definitive =
          (nativeStatus != null && nativeStatus < 500) ||
          error is ArcadeLinkException &&
              error.statusCode != null &&
              error.statusCode! < 500 ||
          (localLocationFailure && saved == null);
      if (definitive &&
          !['OPERATION_PENDING', 'DEVICE_RESULT_UNKNOWN'].contains(code)) {
        await prefs.remove(storageKey);
      }
      if (key.startsWith('device.') && !definitive) {
        throw const ArcadeLinkException(
          '本次会话已失效',
          code: 'DEVICE_RESULT_UNKNOWN',
        );
      }
      rethrow;
    }
  }

  Future<void> device(String action, {bool consent = false}) => _act(() async {
    if (ticketConsumed) {
      expire();
      return;
    }
    final result = await operation(
      'device.${session.ticket}.$action',
      '/api/v1/devices/session/actions',
      {
        'ticket': session.ticket,
        'action': action,
        if (action == 'door.open') 'consent': consent,
      },
      action == 'door.open'
          ? state.geo('checkinGeo')
          : session.machine.machineGeo,
    );
    state = state.copy(
      password: action == 'door.open' ? result : null,
      coinUsed: action == 'coin' || state.coinUsed,
      notice: action == 'coin'
          ? '已投币'
          : action == 'power.on'
          ? '已发送开机请求'
          : null,
    );
    await refresh();
  });
  Future<void> enter() => _act(() async {
    await operation(
      'entry.${session.ticket}',
      path('player/session/start'),
      {'ticket': session.ticket, 'consent': true},
      state.geo('checkinGeo'),
    );
    await refresh();
  });
  Future<void> previewCheckout() => _act(() async {
    state = state.copy(
      preview: await request(path('player/checkout/preview'), body: {}),
    );
  });
  Future<void> checkout() => _act(() async {
    await operation(
      'checkout',
      path('player/checkout/confirm'),
      {},
      state.geo('checkoutGeo'),
    );
    state = state.copy(clearPreview: true, notice: '结账成功，计费已结束');
    await refresh();
  });
  Future<void> redeem(String code) => _act(() async {
    await operation('redeem', path('player/redeem'), {'code': code}, false);
    state = state.copy(notice: '兑换成功');
    await refresh();
  });
  static List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
}
