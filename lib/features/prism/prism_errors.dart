import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:hinata_go/l10n/app_localizations.dart';
import 'package:hinata_go/features/prism/services/prism_api.dart';
import 'package:hinata_go/features/prism/services/prism_location.dart';

// API messages remain transport values; localize only when presenting them.
String _message(Object error) =>
    error is PlatformException ? error.message ?? '' : error.toString();

bool prismSessionExpired(Object error) =>
    error is PrismException && error.code == 'TICKET_EXPIRED' ||
    error is PlatformException &&
        ['session_expired', 'TICKET_EXPIRED'].contains(error.code) ||
    const ['本次会话已失效', '缺少会话凭证'].contains(_message(error));

bool prismAuthRequired(Object error) =>
    error is PrismException && error.statusCode == 401 ||
    error is PlatformException &&
        [
          'authentication_required',
          'AUTHENTICATION_REQUIRED',
        ].contains(error.code) ||
    _message(error) == '请先登录';

String prismErrorMessage(Object error, AppLocalizations l10n) {
  if (error is http.ClientException) return l10n.prismNetworkFailed;
  final code = error is PlatformException
      ? error.code
      : error is PrismException
      ? error.code
      : error is PrismLocationException
      ? error.message
      : '';
  switch (code) {
    case 'location_denied':
      return l10n.prismLocationDenied;
    case 'location_timeout':
      return l10n.prismLocationTimeout;
    case 'location_unavailable':
      return l10n.prismLocationFailed;
    case 'location_busy':
      return l10n.prismLocationBusy;
    case 'network_error':
      return l10n.prismNetworkFailed;
    case 'passkey_invalid':
      return l10n.prismPasskeyFailed;
  }
  if (prismSessionExpired(error)) return l10n.prismExpired;
  return switch (_message(error)) {
    '请先登录' => l10n.prismSignInRequired,
    '请到店再进行登录' => l10n.prismAtArcade,
    '需要定位权限才能确认你在店内' || '需要定位权限才能确认你位于店内' => l10n.prismLocationDenied,
    '定位获取失败' => l10n.prismLocationFailed,
    '机台不可用' || '机台暂时不可用' => l10n.prismMachineUnavailable,
    '操作过于频繁，请稍后重试' => l10n.prismRateLimited,
    '当前无法进行此操作' => l10n.prismRestricted,
    '这个账号暂时无法使用' => l10n.prismAccountUnavailable,
    '卡片不可用或已失效' => l10n.prismCardUnavailable,
    '授权码已失效，请重新登录' => l10n.prismAuthExpired,
    '无效的机台地址' || 'PRiSM 地址无效' => l10n.prismInvalidURL,
    'PRiSM 返回的数据无效' => l10n.prismInvalidResponse,
    '无法识别这个 Passkey' => l10n.prismPasskeyUnknown,
    'Passkey 请求已过期' => l10n.prismPasskeyExpired,
    'Passkey 验证失败' || 'Passkey 登录未完成' => l10n.prismPasskeyFailed,
    '无法打开 MuNET 登录' || '无法打开 MuNET 登录页面' => l10n.prismOpenMunetFailed,
    'MuNET 登录失败' ||
    'MuNET 授权失败' ||
    'MuNET 授权无效，请重新登录' ||
    'MuNET 授权无效，请重试' ||
    'MuNET 登录尚未配置' => l10n.prismMunetFailed,
    _ =>
      (error is PrismException || error is PlatformException) &&
              _message(error).isNotEmpty
          ? _message(error)
          : l10n.prismOperationFailed,
  };
}
