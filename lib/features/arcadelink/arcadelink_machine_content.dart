import 'dart:ui' show ImageFilter, TileMode;

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
  final String? passkeyActionLabel;
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
    const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
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
        Card.filled(
          margin: EdgeInsets.zero,
          elevation: 2,
          shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.24),
          shape: cardShape.copyWith(
            side: BorderSide(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _MachineHero(machine: session.machine),
        ),
        const SizedBox(height: 48),
        if (!authRequired && !browserOnly && !loadingCards && error == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.arcadeLinkSelectCard,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: busy ? null : onLogout,
                icon: const Icon(Icons.logout),
                tooltip: context.l10n.arcadeLinkSignOut,
              ),
            ],
          ),
        const SizedBox(height: 30),
        if (browserOnly)
          _TouchAction(
            label: context.l10n.arcadeLinkContinueLogin,
            onPressed: onContinue,
          )
        else if (authRequired) ...[
          _TouchAction(
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
          _TouchAction(
            label: passkeyAuthenticating
                ? context.l10n.arcadeLinkVerifyingPasskey
                : passkeyActionLabel ?? context.l10n.arcadeLinkSignInPasskey,
            icon: const Icon(Icons.fingerprint, size: 24),
            secondary: true,
            busy: passkeyAuthenticating,
            onPressed: busy || !passkeyAvailable ? null : onAuthenticatePasskey,
          ),
          if (webAuthStarted) ...[
            const SizedBox(height: 20),
            Text(
              context.l10n.arcadeLinkReturnAfterAuth,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _TouchAction(
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
          _TouchAction(
            label: context.l10n.arcadeLinkReloadCards,
            secondary: true,
            onPressed: onReloadCards,
          ),
        ] else
          Card.filled(
            margin: EdgeInsets.zero,
            shape: cardShape,
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
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            machine.name,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final url = machine.heroUrl;
    if (url == null) return info;
    // Both parts paint the same decoded frame; the existing provider owns caching.
    return Image(
      image: kIsWeb ? NetworkImage(url) : CachedNetworkImageProvider(url),
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => info,
      frameBuilder: (context, child, frame, synchronous) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (frame != null) AspectRatio(aspectRatio: 1.5, child: child),
          ClipRect(
            child: Stack(
              children: [
                if (frame != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.22,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 64,
                          sigmaY: 64,
                          tileMode: TileMode.clamp,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                info,
              ],
            ),
          ),
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

class _TouchAction extends StatelessWidget {
  const _TouchAction({
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
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: Theme.of(context).textTheme.titleMedium,
      visualDensity: VisualDensity.standard,
    );
    final leading = busy
        ? SizedBox.square(
            dimension: 24,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          )
        : icon;
    final text = Text(label, textAlign: TextAlign.center);
    return secondary
        ? FilledButton.tonalIcon(
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
                                ? context.l10n.arcadeLinkSignedIn
                                : busy
                                ? sending
                                      ? context.l10n.arcadeLinkSigningIn
                                      : context.l10n.arcadeLinkLocating
                                : context.l10n.arcadeLinkCardEnding(tail),
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
            _TouchAction(
              label: context.l10n.arcadeLinkRetry,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
