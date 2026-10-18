import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/l10n/l10n.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// The layer the toasts live in: above the app, so a toast is never hidden
  /// behind the fixed iOS toolbar or the iPhone Duo vertical bar.
  final GlobalKey<OverlayState> overlayKey = GlobalKey<OverlayState>();

  AppLocalizations get l10n => L10nHolder.current;

  void showSuccess(String message) {
    _showToast(message, Icons.check_circle_rounded, Colors.green);
  }

  void showError(String message) {
    _showToast(message, Icons.error_rounded, Colors.red);
  }

  void showInfo(String message) {
    _showToast(message, Icons.info_rounded, Colors.blue);
  }

  void _showToast(String message, IconData icon, Color color) {
    final overlayState = overlayKey.currentState;
    if (overlayState == null) return;

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        icon: icon,
        color: color,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlayState.insert(overlayEntry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = context.mediaQuery;
    final safeAreaTop = mediaQuery.padding.top;
    final colorScheme = context.colorScheme;
    // iPhone Duo keeps its status cluster and camera in a strip on one side.
    // The toast layer sits above the chrome, so keep the toast clear of that
    // strip itself and let it cover only the chrome.
    final viewPadding = mediaQuery.viewPadding;
    final sideStrip = math.max<double>(
      viewPadding.left > viewPadding.right + 8 ? viewPadding.left : 0,
      viewPadding.right > viewPadding.left + 8 ? viewPadding.right : 0,
    );

    return Positioned(
      top: safeAreaTop + 16,
      left: 16 + (viewPadding.left > viewPadding.right ? sideStrip : 0),
      right: 16 + (viewPadding.right > viewPadding.left ? sideStrip : 0),
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: widget.color, size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
