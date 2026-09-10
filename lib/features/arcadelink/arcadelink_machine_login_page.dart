import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/arcadelink_api.dart';
import '../../services/arcadelink_invocation_service.dart';
import '../../services/arcadelink_native_service.dart';
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
        _page = _isExpired(error) ? _SessionPage.expired : _SessionPage.failed;
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
      if (!launched && mounted) setState(() => _error = '无法打开网页版，请重试');
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开网页版，请重试');
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
        final needsAuth =
            error is ArcadeLinkException && error.statusCode == 401 ||
            error is PlatformException && error.message == '请先登录';
        _authRequired = needsAuth;
        if (_isExpired(error)) _page = _SessionPage.expired;
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
          await _showErrorDialog(arcadeLinkErrorMessage(error));
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
          if (!launched) _error = '无法打开 MuNET 登录页面';
        });
      } catch (_) {
        if (mounted) setState(() => _error = '无法打开 MuNET 登录页面');
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
        await _showErrorDialog(arcadeLinkErrorMessage(error));
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
        if (_isExpired(error)) _page = _SessionPage.expired;
      });
      if (_page != _SessionPage.expired && !_isCancellation(error)) {
        await _showErrorDialog(arcadeLinkErrorMessage(error));
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
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
                            ? '无法读取机台信息'
                            : arcadeLinkErrorMessage(_error!),
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
                            ? '在网页中使用 Passkey'
                            : '使用 Passkey 登录',
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
                tooltip: '返回主页',
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

  bool _isExpired(Object error) =>
      error.toString().contains('会话已失效') || error.toString().contains('缺少会话凭证');

  Future<void> _showErrorDialog(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
