import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../services/arcadelink_api.dart';
import '../../services/arcadelink_location.dart';

// API messages remain transport values; localize only when presenting them.
String _message(Object error) =>
    error is PlatformException ? error.message ?? '' : error.toString();

bool arcadeLinkSessionExpired(Object error) =>
    error is PlatformException && error.code == 'session_expired' ||
    const ['本次会话已失效', '缺少会话凭证'].contains(_message(error));

bool arcadeLinkAuthRequired(Object error) =>
    error is ArcadeLinkException && error.statusCode == 401 ||
    error is PlatformException && error.code == 'authentication_required' ||
    _message(error) == '请先登录';

String arcadeLinkErrorMessage(Object error, AppLocalizations l10n) {
  if (error is http.ClientException) return l10n.arcadeLinkNetworkFailed;
  final code = error is PlatformException
      ? error.code
      : error is ArcadeLinkLocationException
      ? error.message
      : '';
  switch (code) {
    case 'location_denied':
      return l10n.arcadeLinkLocationDenied;
    case 'location_timeout':
      return l10n.arcadeLinkLocationTimeout;
    case 'location_unavailable':
      return l10n.arcadeLinkLocationFailed;
    case 'location_busy':
      return l10n.arcadeLinkLocationBusy;
    case 'network_error':
      return l10n.arcadeLinkNetworkFailed;
    case 'passkey_invalid':
      return l10n.arcadeLinkPasskeyFailed;
  }
  if (arcadeLinkSessionExpired(error)) return l10n.arcadeLinkExpired;
  return switch (_message(error)) {
    '请先登录' => l10n.arcadeLinkSignInRequired,
    '请到店再进行登录' => l10n.arcadeLinkAtArcade,
    '需要定位权限才能确认你在店内' || '需要定位权限才能确认你位于店内' => l10n.arcadeLinkLocationDenied,
    '定位获取失败' => l10n.arcadeLinkLocationFailed,
    '机台不可用' || '机台暂时不可用' => l10n.arcadeLinkMachineUnavailable,
    '操作过于频繁，请稍后重试' => l10n.arcadeLinkRateLimited,
    '当前无法进行此操作' => l10n.arcadeLinkRestricted,
    '这个账号暂时无法使用' => l10n.arcadeLinkAccountUnavailable,
    '卡片不可用或已失效' => l10n.arcadeLinkCardUnavailable,
    '授权码已失效，请重新登录' => l10n.arcadeLinkAuthExpired,
    '无效的机台地址' || 'ArcadeLink 地址无效' => l10n.arcadeLinkInvalidURL,
    'ArcadeLink 返回的数据无效' => l10n.arcadeLinkInvalidResponse,
    '无法识别这个 Passkey' => l10n.arcadeLinkPasskeyUnknown,
    'Passkey 请求已过期' => l10n.arcadeLinkPasskeyExpired,
    'Passkey 验证失败' || 'Passkey 登录未完成' => l10n.arcadeLinkPasskeyFailed,
    '无法打开 MuNET 登录' || '无法打开 MuNET 登录页面' => l10n.arcadeLinkOpenMunetFailed,
    'MuNET 登录失败' ||
    'MuNET 授权失败' ||
    'MuNET 授权无效，请重新登录' ||
    'MuNET 授权无效，请重试' ||
    'MuNET 登录尚未配置' => l10n.arcadeLinkMunetFailed,
    _ => l10n.arcadeLinkOperationFailed,
  };
}
