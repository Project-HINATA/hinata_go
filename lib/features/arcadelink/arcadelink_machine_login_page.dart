import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/arcadelink_api.dart';
import '../../services/arcadelink_invocation_service.dart';
import '../../services/arcadelink_native_service.dart';
import 'arcadelink_machine_content.dart';

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
  bool _loading = true;
  bool _authRequired = false;
  bool _authenticating = false;
  bool _passkeyAuthenticating = false;
  bool _loggingIn = false;
  bool _webAuthStarted = false;
  bool _success = false;
  bool _completed = false;
  bool _sending = false;
  Timer? _completionTimer;
  bool _loadingCards = false;
  String? _activeCardId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(arcadeLinkInvocationProvider).clear();
    });
    _loadMachine();
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadMachine() async {
    final shopCode = widget.shopCode;
    final publicId = widget.publicId;
    _completionTimer?.cancel();
    setState(() {
      _completed = false;
      _loading = true;
      _session = null;
      _cards = const [];
      _error = null;
      _success = false;
      _authRequired = false;
      _webAuthStarted = false;
    });
    try {
      final session = await _api.startMachineSession(
        shopCode: shopCode,
        publicId: publicId,
      );
      if (!mounted ||
          shopCode != widget.shopCode ||
          publicId != widget.publicId) {
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
      });
      if (kIsWeb || ArcadeLinkNativeService.isAvailable) {
        await _loadCards();
      }
    } catch (error) {
      if (!mounted || publicId != widget.publicId) return;
      setState(() {
        _error = error;
        _loading = false;
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
    setState(() => _loadingCards = true);
    try {
      final cards = kIsWeb ? await _api.cards() : await _native.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards.where((card) => card.disabledAt == null).toList();
        _authRequired = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final needsAuth =
            error is ArcadeLinkException && error.statusCode == 401 ||
            error is PlatformException && error.message == '请先登录';
        _authRequired = needsAuth;
        _error = needsAuth ? null : error;
      });
    } finally {
      if (mounted) setState(() => _loadingCards = false);
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating || _passkeyAuthenticating || _loggingIn) return;
    if (ArcadeLinkNativeService.supportsNativeMunet) {
      setState(() {
        _authenticating = true;
        _error = null;
      });
      try {
        await _native.authenticateWithMunet();
        await _loadCards();
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = error);
      } finally {
        if (mounted) setState(() => _authenticating = false);
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
      await _loadCards();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _passkeyAuthenticating = false);
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
      if (mounted) setState(() => _sending = true);
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
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _success = true;
      });
      _completionTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _completed = true);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _loading
                  ? const ArcadeLinkStatusPanel(title: '加载中...', busy: true)
                  : session == null
                  ? ArcadeLinkStatusPanel(
                      title: '无法进入机台会话',
                      message: _error == null
                          ? '无法读取机台信息'
                          : arcadeLinkErrorMessage(_error!),
                      onRetry: _loadMachine,
                    )
                  : ArcadeLinkMachineContent(
                      session: session,
                      cards: _cards,
                      authRequired: _authRequired,
                      authenticating: _authenticating,
                      passkeyAuthenticating: _passkeyAuthenticating,
                      loggingIn: _loggingIn,
                      success: _success,
                      completed: _completed,
                      sending: _sending,
                      webAuthStarted: _webAuthStarted,
                      error: _error,
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
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
