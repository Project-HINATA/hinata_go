import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../services/arcadelink_api.dart';
import '../../services/arcadelink_invocation_service.dart';
import '../../services/arcadelink_native_service.dart';
import 'arcadelink_errors.dart';
import 'arcadelink_machine_content.dart';

enum _SessionPage { loading, failed, session, expired, completed }

class ArcadeLinkMachineLoginPage extends ConsumerStatefulWidget {
  const ArcadeLinkMachineLoginPage({
    required this.shopCode,
    required this.publicId,
    super.key,
  });

  final String shopCode;
  final String publicId;

  @override
  ConsumerState<ArcadeLinkMachineLoginPage> createState() =>
      _ArcadeLinkMachineLoginPageState();
}

class _ArcadeLinkMachineLoginPageState
    extends ConsumerState<ArcadeLinkMachineLoginPage> {
  final _api = ArcadeLinkAPI();
  final _native = ArcadeLinkNativeService();
  ArcadeLinkMachineSession? _session;
  List<ArcadeLinkCard> _cards = const [];
  Object? _error;
  _SessionPage _page = _SessionPage.loading;
  Object? _cardsError;
  bool _authRequired = false;
  bool _authenticating = false;
  bool _passkeyAuthenticating = false;
  bool _loggingIn = false;
  bool _webAuthStarted = false;
  bool _success = false;
  bool _sending = false;
  Timer? _completionTimer;
  bool _loadingCards = false;
  String? _activeCardId;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(arcadeLinkInvocationProvider).clear();
    });
    _loadMachine();
  }

  @override
  void didUpdateWidget(covariant ArcadeLinkMachineLoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopCode != widget.shopCode ||
        oldWidget.publicId != widget.publicId) {
      _loadMachine();
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadMachine() async {
    final version = ++_loadVersion;
    final shopCode = widget.shopCode;
    final publicId = widget.publicId;
    _completionTimer?.cancel();
    setState(() {
      _page = _SessionPage.loading;
      _session = null;
      _cards = const [];
      _error = null;
      _cardsError = null;
      _success = false;
      _authRequired = false;
      _webAuthStarted = false;
      _loadingCards = false;
      _loggingIn = false;
      _authenticating = false;
      _passkeyAuthenticating = false;
      _activeCardId = null;
    });
    try {
      final session = await _api.startMachineSession(
        shopCode: shopCode,
        publicId: publicId,
      );
      if (!mounted || version != _loadVersion) {
        return;
      }
      setState(() {
        _session = session;
        _page = _SessionPage.session;
      });
      if (kIsWeb || ArcadeLinkNativeService.isAvailable) {
        await _loadCards();
      }
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _page = arcadeLinkSessionExpired(error)
            ? _SessionPage.expired
            : _SessionPage.failed;
        _error = error;
      });
    }
  }

  Future<void> _openWebFallback() async {
    final session = _session;
    if (session == null) return;
    try {
      final launched = await launchUrl(
        _api.webFallbackURL(session.ticket),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() => _error = context.l10n.arcadeLinkOpenWebFailed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.arcadeLinkOpenWebFailed);
      }
    }
  }

  Future<void> _loadCards() async {
    if (_loadingCards) return;
    final version = _loadVersion;
    setState(() {
      _loadingCards = true;
      _cardsError = null;
    });
    try {
      final cards = kIsWeb ? await _api.cards() : await _native.loadCards();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _cards = cards.where((card) => card.disabledAt == null).toList();
        _authRequired = false;
        _cardsError = null;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        final needsAuth = arcadeLinkAuthRequired(error);
        _authRequired = needsAuth;
        if (arcadeLinkSessionExpired(error)) _page = _SessionPage.expired;
        _cardsError = needsAuth ? null : error;
      });
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loadingCards = false);
      }
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating || _passkeyAuthenticating || _loggingIn) return;
    final version = _loadVersion;
    if (ArcadeLinkNativeService.supportsNativeMunet) {
      setState(() {
        _authenticating = true;
        _error = null;
      });
      try {
        await _native.authenticateWithMunet();
        if (!mounted || version != _loadVersion) return;
        await _loadCards();
      } catch (error) {
        if (!mounted || version != _loadVersion) return;
        if (!_isCancellation(error)) {
          await _showErrorDialog(arcadeLinkErrorMessage(error, context.l10n));
        }
      } finally {
        if (mounted && version == _loadVersion) {
          setState(() => _authenticating = false);
        }
      }
      return;
    }

    if (kIsWeb) {
      setState(() {
        _authenticating = true;
        _error = null;
      });
      try {
        final launched = await launchUrl(
          _api.munetLoginURL(widget.shopCode, widget.publicId),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        setState(() {
          _webAuthStarted = launched;
          if (!launched) _error = context.l10n.arcadeLinkOpenMunetFailed;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _error = context.l10n.arcadeLinkOpenMunetFailed);
        }
      } finally {
        if (mounted) setState(() => _authenticating = false);
      }
      return;
    }

    await _openWebFallback();
  }

  Future<void> _authenticateWithPasskey() async {
    if (_passkeyAuthenticating || _authenticating || _loggingIn) return;
    final version = _loadVersion;
    setState(() {
      _passkeyAuthenticating = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await _openWebFallback();
        return;
      }
      await _native.authenticateWithPasskey();
      if (!mounted || version != _loadVersion) return;
      await _loadCards();
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      if (!_isCancellation(error)) {
        await _showErrorDialog(arcadeLinkErrorMessage(error, context.l10n));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _passkeyAuthenticating = false);
      }
    }
  }

  Future<void> _login(ArcadeLinkCard card) async {
    if (_loggingIn || _success) return;
    final session = _session;
    if (session == null) return;
    setState(() {
      _sending = false;
      _loggingIn = true;
      _activeCardId = card.id;
      _error = null;
    });
    void onSending() {
      if (mounted && session == _session) setState(() => _sending = true);
    }

    try {
      if (ArcadeLinkNativeService.isAvailable) {
        await _native.loginMachine(
          cardId: card.id,
          ticket: session.ticket,
          onSending: onSending,
        );
      } else {
        await _api.loginMachine(cardId: card.id, ticket: session.ticket);
      }
      if (!mounted || session != _session) return;
      setState(() {
        _loggingIn = false;
        _success = true;
      });
      _completionTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _page = _SessionPage.completed);
      });
    } catch (error) {
      if (!mounted || session != _session) return;
      setState(() {
        _loggingIn = false;
        _error = null;
        if (arcadeLinkSessionExpired(error)) _page = _SessionPage.expired;
      });
      if (_page != _SessionPage.expired && !_isCancellation(error)) {
        await _showErrorDialog(arcadeLinkErrorMessage(error, context.l10n));
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.arcadeLinkSignOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.arcadeLinkSignOutAction),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _authRequired = true;
        _cards = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final contentPadding =
        safePadding + const EdgeInsets.fromLTRB(20, 64, 20, 24);
    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: contentPadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    minHeight: (constraints.maxHeight - contentPadding.vertical)
                        .clamp(0, double.infinity),
                  ),
                  child: Align(
                    alignment: _page == _SessionPage.session
                        ? Alignment.topCenter
                        : Alignment.center,
                    child: switch (_page) {
                      _SessionPage.loading => const ArcadeLinkLoadingPage(),
                      _SessionPage.expired => const ArcadeLinkExpiredPage(),
                      _SessionPage.completed => const ArcadeLinkCompletedPage(),
                      _SessionPage.failed => ArcadeLinkFailurePage(
                        message: _error == null
                            ? context.l10n.arcadeLinkMachineInfoFailed
                            : arcadeLinkErrorMessage(_error!, context.l10n),
                        onRetry: _loadMachine,
                      ),
                      _SessionPage.session => ArcadeLinkMachineContent(
                        session: _session!,
                        cards: _cards,
                        authRequired: _authRequired,
                        authenticating: _authenticating,
                        passkeyAuthenticating: _passkeyAuthenticating,
                        loggingIn: _loggingIn,
                        success: _success,
                        sending: _sending,
                        webAuthStarted: _webAuthStarted,
                        error: _cardsError,
                        loadingCards: _loadingCards,
                        activeCardId: _activeCardId,
                        browserOnly:
                            !kIsWeb && !ArcadeLinkNativeService.isAvailable,
                        passkeyAvailable:
                            kIsWeb ||
                            ArcadeLinkNativeService.supportsNativePasskey,
                        passkeyActionLabel: kIsWeb
                            ? context.l10n.arcadeLinkPasskeyOnWeb
                            : context.l10n.arcadeLinkSignInPasskey,
                        nativeMunetAvailable:
                            ArcadeLinkNativeService.supportsNativeMunet,
                        onAuthenticate: _authenticate,
                        onAuthenticatePasskey: _authenticateWithPasskey,
                        onReloadCards: _loadCards,
                        onLogin: _login,
                        onContinue: _openWebFallback,
                        onLogout: _logout,
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                tooltip: context.l10n.arcadeLinkBackHome,
                onPressed: () => context.go('/scan'),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isCancellation(Object error) =>
      error is PlatformException && error.code == 'authentication_cancelled';

  Future<void> _showErrorDialog(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.arcadeLinkOk),
        ),
      ],
    ),
  );
}
