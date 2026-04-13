import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../providers/current_scan_session_provider.dart';
import '../../../providers/hardware_device_provider.dart';
import '../../../providers/nfc_provider.dart';

class NfcInfoDisplay extends HookConsumerWidget {
  final int contentQuarterTurns;

  const NfcInfoDisplay({required this.contentQuarterTurns, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifecycleState = useAppLifecycleState();
    final inputs = _NfcDisplayInputs.fromRef(
      context,
      ref,
      isPaused: lifecycleState != AppLifecycleState.resumed,
    );
    final isShowingSuccess = useState<bool>(false);
    useEffect(() {
      if (inputs.lastAcceptedScanAt != null) {
        isShowingSuccess.value = true;
        final timer = Timer(const Duration(milliseconds: 1200), () {
          isShowingSuccess.value = false;
        });
        return timer.cancel;
      }
      return null;
    }, [inputs.lastAcceptedScanAt]);

    final displayState = _NfcDisplayState.fromInputs(
      inputs,
      isShowingSuccess: isShowingSuccess.value,
      normalizedQuarterTurns: contentQuarterTurns % 4,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.2, 0.8, 0.2, 1.0),
      decoration: BoxDecoration(
        color: displayState.backgroundColor,
        borderRadius: displayState.borderRadius,
        border: Border.all(
          color: displayState.borderColor,
          width: displayState.borderWidth,
        ),
        boxShadow: displayState.boxShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: displayState.isIOS
              ? () => ref.read(nfcProvider.notifier).startSession()
              : null,
          borderRadius: displayState.borderRadius,
          child: _NfcDisplayBody(displayState: displayState),
        ),
      ),
    );
  }
}

class _NfcDisplayInputs {
  const _NfcDisplayInputs({
    required this.colorScheme,
    required this.lastAcceptedScanAt,
    required this.isCardPresent,
    required this.isUsbAvailable,
    required this.isUsbConnected,
    required this.isScanningNfc,
    required this.isProcessing,
    required this.isIOS,
    required this.isPaused,
  });

  factory _NfcDisplayInputs.fromRef(
    BuildContext context,
    WidgetRef ref, {
    required bool isPaused,
  }) {
    final nfcState = ref.watch(nfcProvider);
    final hardwareDeviceState = ref.watch(hardwareDeviceProvider);

    return _NfcDisplayInputs(
      colorScheme: context.colorScheme,
      lastAcceptedScanAt: ref.watch(
        currentScanSessionProvider.select((s) => s.lastAcceptedScanAt),
      ),
      isCardPresent: ref.watch(
        currentScanSessionProvider.select((s) => s.isCardPresent),
      ),
      isUsbAvailable: hardwareDeviceState.hidAvailable,
      isUsbConnected: hardwareDeviceState.connectedDevice != null,
      isScanningNfc: nfcState.isScanning,
      isProcessing: nfcState.isProcessing,
      isIOS: !kIsWeb && Platform.isIOS,
      isPaused: isPaused,
    );
  }

  final ColorScheme colorScheme;
  final DateTime? lastAcceptedScanAt;
  final bool isCardPresent;
  final bool isUsbAvailable;
  final bool isUsbConnected;
  final bool isScanningNfc;
  final bool isProcessing;
  final bool isIOS;
  final bool isPaused;
}

class _NfcDisplayState {
  const _NfcDisplayState({
    required this.colorScheme,
    required this.borderRadius,
    required this.isIOS,
    required this.isPaused,
    required this.isScanningNfc,
    required this.isUsbAvailable,
    required this.isUsbConnected,
    required this.isProcessing,
    required this.isShowingSuccess,
    required this.isCardPresent,
    required this.isWaitingForCard,
    required this.normalizedQuarterTurns,
  });

  factory _NfcDisplayState.fromInputs(
    _NfcDisplayInputs inputs, {
    required bool isShowingSuccess,
    required int normalizedQuarterTurns,
  }) {
    return _NfcDisplayState(
      colorScheme: inputs.colorScheme,
      borderRadius: BorderRadius.circular(24),
      isIOS: inputs.isIOS,
      isPaused: inputs.isPaused,
      isScanningNfc: inputs.isScanningNfc,
      isUsbAvailable: inputs.isUsbAvailable,
      isUsbConnected: inputs.isUsbConnected,
      isProcessing: inputs.isProcessing,
      isShowingSuccess: isShowingSuccess,
      isCardPresent: inputs.isCardPresent,
      isWaitingForCard:
          !(inputs.isPaused && !(inputs.isIOS && inputs.isScanningNfc)) &&
          !inputs.isProcessing &&
          !isShowingSuccess &&
          !inputs.isCardPresent &&
          (inputs.isScanningNfc || inputs.isUsbConnected),
      normalizedQuarterTurns: normalizedQuarterTurns,
    );
  }

  final ColorScheme colorScheme;
  final BorderRadius borderRadius;
  final bool isIOS;
  final bool isPaused;
  final bool isScanningNfc;
  final bool isUsbAvailable;
  final bool isUsbConnected;
  final bool isProcessing;
  final bool isShowingSuccess;
  final bool isCardPresent;
  final bool isWaitingForCard;
  final int normalizedQuarterTurns;

  bool get shouldShowPausedPrompt => isPaused && !(isIOS && isScanningNfc);
  bool get isHighlighted => isShowingSuccess || isCardPresent;
  bool get isSidewaysContent => normalizedQuarterTurns.isOdd;

  Color get backgroundColor => isHighlighted
      ? colorScheme.primaryContainer.withValues(alpha: 0.4)
      : colorScheme.surfaceContainer;

  Color get borderColor => isHighlighted
      ? colorScheme.primary.withValues(alpha: 0.5)
      : colorScheme.outlineVariant.withValues(alpha: 0.5);

  double get borderWidth => isHighlighted ? 1.5 : 1.0;

  List<BoxShadow> get boxShadow => isHighlighted
      ? [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ]
      : const [];
}

class _NfcDisplayBody extends StatelessWidget {
  const _NfcDisplayBody({required this.displayState});

  final _NfcDisplayState displayState;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (displayState.isWaitingForCard)
          _ScanningBackground(borderRadius: displayState.borderRadius),
        _CenterDisplayContent(displayState: displayState),
        _StatusMarkersAnchor(sideways: displayState.isSidewaysContent),
        if (displayState.isProcessing) const _NfcProcessingOverlay(),
      ],
    );
  }
}

class _ScanningBackground extends StatelessWidget {
  const _ScanningBackground({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: const _ScanningRippleBackground(),
        ),
      ),
    );
  }
}

class _CenterDisplayContent extends StatelessWidget {
  const _CenterDisplayContent({required this.displayState});

  final _NfcDisplayState displayState;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          reverseDuration: const Duration(milliseconds: 400),
          switchInCurve: const Cubic(0.2, 0.8, 0.2, 1.0),
          switchOutCurve: Curves.easeInCirc,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: displayState.isShowingSuccess
              ? const KeyedSubtree(
                  key: ValueKey('success'),
                  child: _FluidMorphSuccess(),
                )
              : KeyedSubtree(
                  key: const ValueKey('prompt'),
                  child: _ScanningPrompt(
                    isIOS: displayState.isIOS,
                    isNfcActive: displayState.isScanningNfc,
                    isUsbActive: displayState.isUsbConnected,
                    isPaused: displayState.isPaused,
                    sideways: displayState.isSidewaysContent,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatusMarkersAnchor extends StatelessWidget {
  const _StatusMarkersAnchor({required this.sideways});

  final bool sideways;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      right: 20,
      child: _StatusMarkers(sideways: sideways),
    );
  }
}

class _ScanningRippleBackground extends HookWidget {
  const _ScanningRippleBackground();

  static const _rippleCurve = Cubic(0.22, 0.61, 0.36, 1.0);
  static const _circlePhaseEnd = 0.48;
  static const _spawnInterval = 0.84;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 4700),
    )..repeat();

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _RippleMetrics.fromConstraints(constraints);

        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final breathingGlow =
                0.5 + 0.5 * math.sin(controller.value * 2 * math.pi);

            return Stack(
              children: [
                _RippleGlow(
                  colorScheme: colorScheme,
                  breathingGlow: breathingGlow,
                ),
                ..._buildWaves(colorScheme, controller.value, metrics),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildWaves(
    ColorScheme colorScheme,
    double controllerValue,
    _RippleMetrics metrics,
  ) {
    final phase = controllerValue * _spawnInterval;
    final waveAges = [phase + _spawnInterval, phase].where((age) => age <= 1.0);

    return waveAges.map((progress) {
      return _RippleWave(
        progress: progress,
        metrics: metrics,
        colorScheme: colorScheme,
      );
    }).toList();
  }
}

class _FluidMorphSuccess extends HookWidget {
  const _FluidMorphSuccess();

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 800),
    )..forward();

    final entranceProgress = CurvedAnimation(
      parent: controller,
      curve: const Cubic(0.2, 0.8, 0.2, 1.0),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final morphValue = entranceProgress.value;
        return _SuccessMorphContent(
          morphValue: morphValue,
          isCheckmark: morphValue > 0.45,
        );
      },
    );
  }
}

class _SuccessMorphContent extends StatelessWidget {
  const _SuccessMorphContent({
    required this.morphValue,
    required this.isCheckmark,
  });

  final double morphValue;
  final bool isCheckmark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scale: morphValue * 1.6,
          child: Opacity(
            opacity: morphValue.clamp(0.0, 0.3),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ),
        Transform.scale(
          scale: morphValue < 0.45
              ? (1.0 - morphValue * 2.2).clamp(0.0, 1.0)
              : ((morphValue - 0.45) * 1.8 + 1.0).clamp(0.0, 1.2),
          child: Transform.rotate(
            angle: (1.0 - morphValue) * 0.4 * math.pi,
            child: Icon(
              isCheckmark ? Icons.check_rounded : Icons.contactless_outlined,
              size: 64,
              color: isCheckmark
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanningPrompt extends StatelessWidget {
  final bool isIOS;
  final bool isNfcActive;
  final bool isUsbActive;
  final bool isPaused;
  final bool sideways;

  const _ScanningPrompt({
    required this.isIOS,
    required this.isNfcActive,
    required this.isUsbActive,
    required this.isPaused,
    required this.sideways,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineConfig = _PromptLineConfig.fromSideways(sideways);
        final promptText = _PromptText.fromState(
          context,
          isIOS: isIOS,
          isNfcActive: isNfcActive,
          isUsbActive: isUsbActive,
        );
        final textBlockMaxWidth = _PromptLayout.maxWidth(
          constraints.maxWidth,
          sideways: sideways,
        );
        final shouldShowPausedPrompt = isPaused && !(isIOS && isNfcActive);

        if (shouldShowPausedPrompt) {
          return _PausedPromptContent(
            styles: _PromptStyles.paused(context),
            textBlockMaxWidth: textBlockMaxWidth,
            lineConfig: lineConfig,
          );
        }

        return _ActivePromptContent(
          promptText: promptText,
          textBlockMaxWidth: textBlockMaxWidth,
          maxLines: lineConfig.bodyMaxLines,
        );
      },
    );
  }
}

class _StatusMarkers extends ConsumerWidget {
  final bool sideways;

  const _StatusMarkers({required this.sideways});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nfcStatus = ref.watch(nfcProvider).status;
    final hardwareDeviceState = ref.watch(hardwareDeviceProvider);
    final isUsbAvailable = hardwareDeviceState.hidAvailable;
    final isUsbConnected = hardwareDeviceState.connectedDevice != null;

    return Flex(
      direction: sideways ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (nfcStatus != NfcStatus.unsupported)
          _StatusMarkerIcon(
            icon: Icons.contactless_rounded,
            enabled: nfcStatus != NfcStatus.disabled,
          ),
        if (isUsbAvailable) ...[
          _StatusMarkerSpacer(sideways: sideways),
          _StatusMarkerIcon(icon: Icons.usb_rounded, enabled: isUsbConnected),
        ],
      ],
    );
  }
}

class _PromptLayout {
  static double maxWidth(double availableWidth, {required bool sideways}) {
    return math.max(120.0, availableWidth - (sideways ? 72 : 0));
  }
}

class _PromptLineConfig {
  const _PromptLineConfig({
    required this.titleMaxLines,
    required this.bodyMaxLines,
  });

  factory _PromptLineConfig.fromSideways(bool sideways) {
    return _PromptLineConfig(
      titleMaxLines: sideways ? 3 : 2,
      bodyMaxLines: sideways ? 4 : 3,
    );
  }

  final int titleMaxLines;
  final int bodyMaxLines;
}

class _PromptText {
  const _PromptText({
    required this.text,
    required this.icon,
    required this.color,
  });

  factory _PromptText.fromState(
    BuildContext context, {
    required bool isIOS,
    required bool isNfcActive,
    required bool isUsbActive,
  }) {
    final colorScheme = context.colorScheme;
    final isActive = isNfcActive || isUsbActive;
    final isIosScanning = isIOS && isNfcActive;

    return _PromptText(
      text: isIosScanning
          ? context.l10n.nfcIosAlert
          : isIOS
          ? context.l10n.tapToScan
          : isActive
          ? context.l10n.holdCardNearReader
          : context.l10n.nfcInactive,
      icon: isIosScanning
          ? Icons.phone_iphone_rounded
          : isActive
          ? Icons.contactless_rounded
          : Icons.touch_app_rounded,
      color: isActive
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
    );
  }

  final String text;
  final IconData icon;
  final Color color;
}

class _PromptStyles {
  static TextStyle? pausedTitle(BuildContext context) {
    return context.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      letterSpacing: 0.5,
    );
  }

  static TextStyle? pausedDescription(BuildContext context) {
    return context.textTheme.labelMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    );
  }

  static _PausedPromptStyles paused(BuildContext context) {
    return _PausedPromptStyles(
      titleStyle: pausedTitle(context),
      descriptionStyle: pausedDescription(context),
    );
  }
}

class _PausedPromptStyles {
  const _PausedPromptStyles({
    required this.titleStyle,
    required this.descriptionStyle,
  });

  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;
}

class _PromptTextBlock extends StatelessWidget {
  const _PromptTextBlock({
    required this.text,
    required this.maxWidth,
    required this.maxLines,
    required this.style,
  });

  final String text;
  final double maxWidth;
  final int maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _PausedPromptContent extends StatelessWidget {
  const _PausedPromptContent({
    required this.styles,
    required this.textBlockMaxWidth,
    required this.lineConfig,
  });

  final _PausedPromptStyles styles;
  final double textBlockMaxWidth;
  final _PromptLineConfig lineConfig;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.pause_circle_outline_rounded,
          size: 32,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
        const SizedBox(height: 12),
        _PromptTextBlock(
          text: l10n.scanPaused,
          maxWidth: textBlockMaxWidth,
          maxLines: lineConfig.titleMaxLines,
          style: styles.titleStyle,
        ),
        const SizedBox(height: 4),
        _PromptTextBlock(
          text: l10n.scanPausedDescription,
          maxWidth: textBlockMaxWidth,
          maxLines: lineConfig.bodyMaxLines,
          style: styles.descriptionStyle,
        ),
      ],
    );
  }
}

class _ActivePromptContent extends StatelessWidget {
  const _ActivePromptContent({
    required this.promptText,
    required this.textBlockMaxWidth,
    required this.maxLines,
  });

  final _PromptText promptText;
  final double textBlockMaxWidth;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(promptText.icon, size: 36, color: promptText.color),
        const SizedBox(height: 12),
        _PromptTextBlock(
          text: promptText.text,
          maxWidth: textBlockMaxWidth,
          maxLines: maxLines,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: promptText.color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _StatusMarkerIcon extends StatelessWidget {
  const _StatusMarkerIcon({required this.icon, required this.enabled});

  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: 14,
      color: enabled
          ? context.colorScheme.primary.withValues(alpha: 0.5)
          : context.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
    );
  }
}

class _StatusMarkerSpacer extends StatelessWidget {
  const _StatusMarkerSpacer({required this.sideways});

  final bool sideways;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: sideways ? 0 : 8, height: sideways ? 8 : 0);
  }
}

class _RippleMetrics {
  const _RippleMetrics({
    required this.width,
    required this.height,
    required this.shortestSide,
    required this.startDiameter,
  });

  factory _RippleMetrics.fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final shortestSide = math.min(width, height);

    return _RippleMetrics(
      width: width,
      height: height,
      shortestSide: shortestSide,
      startDiameter: shortestSide * 0.22,
    );
  }

  final double width;
  final double height;
  final double shortestSide;
  final double startDiameter;
}

class _RippleGlow extends StatelessWidget {
  const _RippleGlow({required this.colorScheme, required this.breathingGlow});

  final ColorScheme colorScheme;
  final double breathingGlow;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.18,
            colors: [
              colorScheme.primary.withValues(
                alpha: 0.035 + breathingGlow * 0.02,
              ),
              colorScheme.primary.withValues(alpha: 0.016),
              Colors.transparent,
            ],
            stops: const [0.0, 0.62, 1.0],
          ),
        ),
      ),
    );
  }
}

class _RippleWave extends StatelessWidget {
  const _RippleWave({
    required this.progress,
    required this.metrics,
    required this.colorScheme,
  });

  final double progress;
  final _RippleMetrics metrics;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final geometry = _RippleGeometry.fromProgress(progress, metrics);

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: geometry.insetX,
          vertical: geometry.insetY,
        ),
        child: Opacity(
          opacity: geometry.opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(geometry.cornerRadius),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.78),
                width: 1.15 - progress * 0.18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RippleGeometry {
  const _RippleGeometry({
    required this.cornerRadius,
    required this.insetX,
    required this.insetY,
    required this.opacity,
  });

  factory _RippleGeometry.fromProgress(
    double progress,
    _RippleMetrics metrics,
  ) {
    final curved = _ScanningRippleBackground._rippleCurve.transform(
      progress.clamp(0.0, 1.0),
    );

    late final double rippleWidth;
    late final double rippleHeight;
    late final double cornerRadius;

    if (curved <= _ScanningRippleBackground._circlePhaseEnd) {
      final circleT = curved / _ScanningRippleBackground._circlePhaseEnd;
      final diameter =
          metrics.startDiameter +
          (metrics.shortestSide - metrics.startDiameter) * circleT;
      rippleWidth = diameter;
      rippleHeight = diameter;
      cornerRadius = diameter / 2;
    } else {
      final rectT =
          (curved - _ScanningRippleBackground._circlePhaseEnd) /
          (1.0 - _ScanningRippleBackground._circlePhaseEnd);
      rippleWidth =
          metrics.shortestSide + (metrics.width - metrics.shortestSide) * rectT;
      rippleHeight =
          metrics.shortestSide +
          (metrics.height - metrics.shortestSide) * rectT;
      final startRadius = metrics.shortestSide / 2;
      cornerRadius = 24 + (startRadius - 24) * (1.0 - rectT);
    }

    return _RippleGeometry(
      cornerRadius: cornerRadius,
      insetX: math.max(0.0, (metrics.width - rippleWidth) / 2),
      insetY: math.max(0.0, (metrics.height - rippleHeight) / 2),
      opacity: math.max(0.0, (1.0 - progress) * 0.2 - progress * 0.035),
    );
  }

  final double cornerRadius;
  final double insetX;
  final double insetY;
  final double opacity;
}

class _NfcProcessingOverlay extends StatelessWidget {
  const _NfcProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
