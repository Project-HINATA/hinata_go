import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/arcadelink_api.dart';

/// Presentation only: the page owns authentication and machine requests.
class ArcadeLinkMachineContent extends StatelessWidget {
  const ArcadeLinkMachineContent({
    required this.session,
    required this.cards,
    required this.authRequired,
    required this.authenticating,
    required this.passkeyAuthenticating,
    required this.loggingIn,
    required this.success,
    required this.webAuthStarted,
    required this.error,
    required this.onAuthenticate,
    required this.onAuthenticatePasskey,
    required this.onReloadCards,
    required this.onLogin,
    required this.onContinue,
    this.loadingCards = false,
    this.sending = false,
    this.browserOnly = false,
    this.passkeyAvailable = false,
    this.passkeyActionLabel = '使用 Passkey 登录',
    this.nativeMunetAvailable = false,
    this.onLogout,
    this.activeCardId,
    super.key,
  });

  final ArcadeLinkMachineSession session;
  final List<ArcadeLinkCard> cards;
  final bool authRequired,
      authenticating,
      passkeyAuthenticating,
      loggingIn,
      success,
      webAuthStarted;
  final bool loadingCards, browserOnly, passkeyAvailable, nativeMunetAvailable;
  final bool sending;
  final String passkeyActionLabel;
  final String? activeCardId;
  final Object? error;
  final VoidCallback onAuthenticate,
      onAuthenticatePasskey,
      onReloadCards,
      onContinue;
  final ValueChanged<ArcadeLinkCard> onLogin;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy =
        authenticating ||
        passkeyAuthenticating ||
        loggingIn ||
        loadingCards ||
        success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session.machine.heroUrl case final String url)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  frameBuilder: (context, child, frame, synchronous) =>
                      frame == null
                      ? const SizedBox.shrink()
                      : AspectRatio(aspectRatio: 1.5, child: child),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.machine.shopName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.machine.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        if (!authRequired && !browserOnly && !loadingCards && error == null)
          Row(
            children: [
              Text(
                '选择卡片',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: busy ? null : onLogout,
                icon: const Icon(Icons.logout),
                tooltip: '退出账号',
              ),
            ],
          ),
        const SizedBox(height: 30),
        if (browserOnly)
          _TouchAction(label: '继续登录', onPressed: onContinue)
        else if (authRequired) ...[
          _TouchAction(
            label: authenticating ? '正在连接 MuNET…' : '使用 MuNET 登录',
            busy: authenticating,
            onPressed: busy ? null : onAuthenticate,
          ),
          const SizedBox(height: 12),
          _TouchAction(
            label: passkeyAuthenticating ? '正在验证 Passkey…' : passkeyActionLabel,
            secondary: true,
            busy: passkeyAuthenticating,
            onPressed: busy || !passkeyAvailable ? null : onAuthenticatePasskey,
          ),
          if (webAuthStarted) ...[
            const SizedBox(height: 20),
            Text(
              '完成授权后，返回这里刷新卡片。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _TouchAction(
              label: '重新加载卡片',
              secondary: true,
              onPressed: busy ? null : onReloadCards,
            ),
          ],
        ] else if (loadingCards)
          Semantics(
            label: '正在加载卡片',
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (error != null)
          ArcadeLinkStatusPanel(
            title: '无法加载卡片',
            message: arcadeLinkErrorMessage(error!),
            onRetry: onReloadCards,
          )
        else if (cards.isEmpty) ...[
          Text(
            '还没有可用卡片，请先在 ArcadeLink 添加卡片',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          _TouchAction(
            label: '重新加载卡片',
            secondary: true,
            onPressed: onReloadCards,
          ),
        ] else
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 24),
                  _CardLoginTile(
                    card: cards[i],
                    busy: loggingIn && cards[i].id == activeCardId,
                    sending: sending,
                    success: success && cards[i].id == activeCardId,
                    dimmed: busy && cards[i].id != activeCardId,
                    onPressed: busy ? null : () => onLogin(cards[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

String arcadeLinkErrorMessage(Object error) {
  final message = error is PlatformException
      ? error.message ?? '操作失败，请重试'
      : error.toString();
  if (message.contains('定位权限') || message.contains('denied')) {
    return '需要定位权限才能确认你在店内';
  }
  if (message.contains('机台') ||
      message.contains('502') ||
      message.contains('404')) {
    return '这台机台暂时不可用，请稍后重试';
  }
  if (message.contains('Exception') || message.contains('请求失败')) {
    return '操作失败，请稍后重试';
  }
  return message;
}

class ArcadeLinkLoadingPage extends StatelessWidget {
  const ArcadeLinkLoadingPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(semanticsLabel: '正在加载'));
}

class ArcadeLinkFailurePage extends StatelessWidget {
  const ArcadeLinkFailurePage({
    required this.message,
    required this.onRetry,
    super.key,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ArcadeLinkStatusPanel(
    title: '无法进入机台会话',
    message: message,
    onRetry: onRetry,
  );
}

class ArcadeLinkExpiredPage extends StatelessWidget {
  const ArcadeLinkExpiredPage({super.key});

  @override
  Widget build(BuildContext context) => const ArcadeLinkStatusPanel(
    title: '本次会话已失效',
    message: '请重新碰一下 NFC 或重新扫描二维码。',
    icon: Icons.history,
  );
}

class ArcadeLinkCompletedPage extends StatelessWidget {
  const ArcadeLinkCompletedPage({super.key});

  @override
  Widget build(BuildContext context) => const ArcadeLinkStatusPanel(
    title: '本次登录已完成',
    message: '可以关闭此页面',
    icon: Icons.check_circle_outline,
  );
}

class _TouchAction extends StatelessWidget {
  const _TouchAction({
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary, busy;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: Theme.of(context).textTheme.titleMedium,
      visualDensity: VisualDensity.standard,
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return secondary
        ? FilledButton.tonal(style: style, onPressed: onPressed, child: child)
        : FilledButton(style: style, onPressed: onPressed, child: child);
  }
}

class _CardLoginTile extends StatelessWidget {
  const _CardLoginTile({
    required this.card,
    required this.busy,
    required this.sending,
    required this.success,
    required this.dimmed,
    required this.onPressed,
  });
  final ArcadeLinkCard card;
  final bool busy, sending, success, dimmed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tail = card.accessCode.length > 4
        ? card.accessCode.substring(card.accessCode.length - 4)
        : card.accessCode;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.label, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Semantics(
                          liveRegion: busy || success,
                          child: Text(
                            success
                                ? '已登录'
                                : busy
                                ? sending
                                      ? '正在登录…'
                                      : '确认位置…'
                                : '尾号 $tail',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (busy)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      success ? Icons.check : Icons.chevron_right,
                      color: success
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ArcadeLinkStatusPanel extends StatelessWidget {
  const ArcadeLinkStatusPanel({
    required this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.busy = false,
    this.onRetry,
    super.key,
  });
  final String title;
  final String? message;
  final IconData icon;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy)
            const Center(child: CircularProgressIndicator())
          else
            Icon(icon, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            _TouchAction(label: '重试', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}
