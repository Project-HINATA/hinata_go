import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../l10n/l10n.dart';
import '../../services/arcadelink_api.dart';
import 'arcadelink_errors.dart';

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
    this.passkeyActionLabel,
    this.nativeMunetAvailable = false,
    this.onLogout,
    this.onManageCards,
    this.activeCardId,
    this.beforeCards,
    this.afterCards,
    this.showCards = true,
    super.key,
  });

  final Widget? beforeCards, afterCards;
  final bool showCards;
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
  final String? passkeyActionLabel;
  final String? activeCardId;
  final Object? error;
  final VoidCallback onAuthenticate,
      onAuthenticatePasskey,
      onReloadCards,
      onContinue;
  final ValueChanged<ArcadeLinkCard> onLogin;
  final VoidCallback? onLogout;
  final VoidCallback? onManageCards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
    final busy =
        authenticating ||
        passkeyAuthenticating ||
        loggingIn ||
        loadingCards ||
        success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          elevation: 2,
          shadowColor: theme.colorScheme.shadow.withValues(alpha: .18),
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .4),
              width: .5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _MachineHero(machine: session.machine),
        ),
        if (beforeCards != null) ...[const SizedBox(height: 40), beforeCards!],
        if (showCards) ...[
          SizedBox(
            height: beforeCards != null
                ? 28
                : session.machine.unified
                ? 40
                : 48,
          ),
          if (!authRequired && !browserOnly && !loadingCards && error == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.arcadeLinkSelectCard,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
          if (!authRequired && !loadingCards) const SizedBox(height: 24),
          if (browserOnly)
            ArcadeLinkAction(
              label: context.l10n.arcadeLinkContinueLogin,
              onPressed: onContinue,
            )
          else if (authRequired) ...[
            ArcadeLinkAction(
              label: authenticating
                  ? context.l10n.arcadeLinkConnectingMunet
                  : context.l10n.arcadeLinkSignInMunet,
              icon: Image.asset(
                'assets/munet-logo.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              busy: authenticating,
              onPressed: busy ? null : onAuthenticate,
            ),
            const SizedBox(height: 12),
            ArcadeLinkAction(
              label: passkeyAuthenticating
                  ? context.l10n.arcadeLinkVerifyingPasskey
                  : passkeyActionLabel ?? context.l10n.arcadeLinkSignInPasskey,
              icon: const Icon(Icons.fingerprint, size: 24),
              secondary: true,
              busy: passkeyAuthenticating,
              onPressed: busy || !passkeyAvailable
                  ? null
                  : onAuthenticatePasskey,
            ),
            if (webAuthStarted) ...[
              const SizedBox(height: 20),
              Text(
                context.l10n.arcadeLinkReturnAfterAuth,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ArcadeLinkAction(
                label: context.l10n.arcadeLinkReloadCards,
                secondary: true,
                onPressed: busy ? null : onReloadCards,
              ),
            ],
          ] else if (loadingCards)
            Semantics(
              label: context.l10n.arcadeLinkLoadingCards,
              child: const Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            ArcadeLinkStatusPanel(
              title: context.l10n.arcadeLinkCardsFailed,
              message: arcadeLinkErrorMessage(error!, context.l10n),
              onRetry: onReloadCards,
            )
          else if (cards.isEmpty) ...[
            Text(
              context.l10n.arcadeLinkNoCards,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            if (onManageCards != null) ...[
              ArcadeLinkAction(
                label: context.l10n.addCard,
                secondary: true,
                onPressed: onManageCards,
              ),
              const SizedBox(height: 24),
            ],
            ArcadeLinkAction(
              label: context.l10n.arcadeLinkReloadCards,
              secondary: true,
              onPressed: onReloadCards,
            ),
          ] else
            Card.filled(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerLow,
              shape: cardShape,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
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
        ?afterCards,
      ],
    );
  }
}

class _MachineHero extends StatelessWidget {
  const _MachineHero({required this.machine});
  final ArcadeLinkMachine machine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            machine.shopName,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            machine.name,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final url = machine.heroUrl;
    if (url == null) return info;
    return Image(
      image: kIsWeb ? NetworkImage(url) : CachedNetworkImageProvider(url),
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => info,
      frameBuilder: (context, child, frame, synchronous) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (frame != null) AspectRatio(aspectRatio: 1.5, child: child),
          info,
        ],
      ),
    );
  }
}

class ArcadeLinkLoadingPage extends StatelessWidget {
  const ArcadeLinkLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: CircularProgressIndicator(
      semanticsLabel: context.l10n.arcadeLinkLoading,
    ),
  );
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
    title: context.l10n.arcadeLinkSessionFailed,
    message: message,
    onRetry: onRetry,
  );
}

class ArcadeLinkExpiredPage extends StatelessWidget {
  const ArcadeLinkExpiredPage({super.key});

  @override
  Widget build(BuildContext context) => ArcadeLinkStatusPanel(
    title: context.l10n.arcadeLinkExpired,
    message: context.l10n.arcadeLinkScanAgain,
    icon: Icons.history,
  );
}

class ArcadeLinkCompletedPage extends StatelessWidget {
  const ArcadeLinkCompletedPage({super.key});

  @override
  Widget build(BuildContext context) => ArcadeLinkStatusPanel(
    title: context.l10n.arcadeLinkCompleted,
    message: context.l10n.arcadeLinkClosePage,
    icon: Icons.check_circle_outline,
  );
}

class ArcadeLinkAction extends StatelessWidget {
  const ArcadeLinkAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool secondary, busy;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
    );
    final leading = busy
        ? SizedBox.square(
            dimension: 24,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: onPressed == null
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .38)
                    : secondary
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          )
        : icon;
    final text = Text(label, textAlign: TextAlign.center);
    return secondary
        ? OutlinedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: leading,
            label: text,
          )
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: leading,
            label: text,
          );
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
      child: ListTile(
        onTap: onPressed,
        enabled: onPressed != null,
        minTileHeight: 88,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        title: Text(card.label, style: theme.textTheme.titleLarge),
        subtitle: Semantics(
          liveRegion: busy || success,
          child: Text(
            success
                ? context.l10n.arcadeLinkSignedIn
                : busy
                ? sending
                      ? context.l10n.arcadeLinkSigningIn
                      : context.l10n.arcadeLinkLocating
                : context.l10n.arcadeLinkCardEnding(tail),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                success ? Icons.check : Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
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
            style: theme.textTheme.headlineSmall,
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
            ArcadeLinkAction(
              label: context.l10n.arcadeLinkRetry,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
