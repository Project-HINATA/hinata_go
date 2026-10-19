import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../models/remote_instance.dart';
import '../../models/scanning_mode.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/device_orientation_provider.dart';
import '../../providers/display_rotation_provider.dart';
import '../app_layout.dart';
import '../components/reader/current_scan_result_panel.dart';
import '../components/reader/instance_card.dart';
import '../components/reader/nfc_info_display.dart';
import '../widgets/app_scaffold.dart';

class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  static const double _contentSpacing = 32;
  static const double _contentBottomSpacing = 16;
  static const double _goldenRatio = 1.61803398875;
  static const double _desktopLandscapePlaceholderMaxHeight = 420;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(scanningModeProvider);
    final activeInstance = ref.watch(activeInstanceProvider);
    final layout = context.appLayout;
    final androidDisplayRotation = ref.watch(androidDisplayRotationProvider);
    final iosDeviceTopOnRight = ref.watch(iosDeviceTopOnRightProvider);
    final deviceTopOnRight = layout.resolveDeviceTopOnRight(
      androidDisplayRotation: androidDisplayRotation,
      iosDeviceTopOnRight: iosDeviceTopOnRight,
    );
    final modeSelector = _ModeSelector(
      mode: mode,
      onModeChanged: (newMode) {
        ref.read(scanningModeProvider.notifier).setMode(newMode);
      },
    );
    final dynamicContent = _DynamicScanContent(
      mode: mode,
      activeInstance: activeInstance,
    );

    return AppScaffold(
      backgroundColor: context.colorScheme.surface,
      titleWidget: _buildAppBarTitle(context),
      materialAppBar: _buildAppBar(context),
      body: SafeArea(
        top: layout.isLandscape || useCupertinoChrome,
        bottom: false,
        child: _ScanPageBody(
          layout: layout,
          deviceTopOnRight: deviceTopOnRight,
          modeSelector: modeSelector,
          dynamicContent: dynamicContent,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(title: _buildAppBarTitle(context), centerTitle: false);
  }

  Widget _buildAppBarTitle(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/logo.svg',
          height: 24,
          colorFilter: ColorFilter.mode(
            context.colorScheme.onSurface,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 8),
        const Text('HINATA Go'),
      ],
    );
  }
}

class _ScanPageBody extends StatelessWidget {
  const _ScanPageBody({
    required this.layout,
    required this.deviceTopOnRight,
    required this.modeSelector,
    required this.dynamicContent,
  });

  final AppLayoutInfo layout;
  final bool deviceTopOnRight;
  final Widget modeSelector;
  final Widget dynamicContent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return layout.isLandscape
                  ? _ScanLandscapeBody(
                      layout: layout,
                      deviceTopOnRight: deviceTopOnRight,
                      constraints: constraints,
                      modeSelector: modeSelector,
                      dynamicContent: dynamicContent,
                    )
                  : _ScanPortraitBody(
                      constraints: constraints,
                      modeSelector: modeSelector,
                      dynamicContent: dynamicContent,
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _ScanLandscapeBody extends StatelessWidget {
  const _ScanLandscapeBody({
    required this.layout,
    required this.deviceTopOnRight,
    required this.constraints,
    required this.modeSelector,
    required this.dynamicContent,
  });

  final AppLayoutInfo layout;
  final bool deviceTopOnRight;
  final BoxConstraints constraints;
  final Widget modeSelector;
  final Widget dynamicContent;

  @override
  Widget build(BuildContext context) {
    final placeholderHeight = layout.isPhone
        ? constraints.maxHeight
        : constraints.maxHeight > ScanPage._desktopLandscapePlaceholderMaxHeight
        ? ScanPage._desktopLandscapePlaceholderMaxHeight
        : constraints.maxHeight;
    final controlColumn = _ScanControlColumn(
      // Landscape phones used to drop the switcher entirely on iOS. Where a
      // navigation rail exists (Android) the rail footer already carries it.
      showInlineModeSelector:
          !layout.isCompactLandscapePhone || useCupertinoChrome,
      modeSelector: modeSelector,
      dynamicContent: dynamicContent,
    );
    final controlColumnPane = Expanded(
      child: SizedBox(height: constraints.maxHeight, child: controlColumn),
    );
    final placeholder = _ScanPlaceholder(
      width: placeholderHeight / ScanPage._goldenRatio,
      height: placeholderHeight,
      contentQuarterTurns: deviceTopOnRight ? 1 : 3,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (deviceTopOnRight) controlColumnPane,
        if (deviceTopOnRight) const SizedBox(width: ScanPage._contentSpacing),
        placeholder,
        if (!deviceTopOnRight) const SizedBox(width: ScanPage._contentSpacing),
        if (!deviceTopOnRight) controlColumnPane,
      ],
    );
  }
}

class _ScanPortraitBody extends StatelessWidget {
  const _ScanPortraitBody({
    required this.constraints,
    required this.modeSelector,
    required this.dynamicContent,
  });

  final BoxConstraints constraints;
  final Widget modeSelector;
  final Widget dynamicContent;

  @override
  Widget build(BuildContext context) {
    final bottomContentPadding =
        context.mediaQuery.padding.bottom + ScanPage._contentBottomSpacing;

    return _ScrollOnlyWhenOverflowing(
      maxHeight: constraints.maxHeight,
      padding: EdgeInsets.only(bottom: bottomContentPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScanPlaceholder(
            width: constraints.maxWidth,
            height: constraints.maxWidth / ScanPage._goldenRatio,
            contentQuarterTurns: 0,
          ),
          const SizedBox(height: 16),
          Center(child: modeSelector),
          const SizedBox(height: 24),
          dynamicContent,
        ],
      ),
    );
  }
}

/// A scroll view that only claims vertical drags when its content actually
/// overflows. When everything fits, the drag belongs to the shell's swipe
/// navigation instead of being swallowed by an invisible scrollable.
class _ScrollOnlyWhenOverflowing extends StatefulWidget {
  const _ScrollOnlyWhenOverflowing({
    required this.maxHeight,
    required this.padding,
    required this.child,
  });

  final double maxHeight;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<_ScrollOnlyWhenOverflowing> createState() =>
      _ScrollOnlyWhenOverflowingState();
}

class _ScrollOnlyWhenOverflowingState
    extends State<_ScrollOnlyWhenOverflowing> {
  final _contentKey = GlobalKey();
  bool _contentFits = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _contentKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final fits =
          box.size.height + widget.padding.vertical <= widget.maxHeight;
      if (fits != _contentFits) {
        setState(() => _contentFits = fits);
      }
    });

    return SingleChildScrollView(
      clipBehavior: Clip.none,
      physics: _contentFits
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      child: KeyedSubtree(key: _contentKey, child: widget.child),
    );
  }
}

class _ScanPlaceholder extends StatelessWidget {
  const _ScanPlaceholder({
    required this.width,
    required this.height,
    required this.contentQuarterTurns,
  });

  final double width;
  final double height;
  final int contentQuarterTurns;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: NfcInfoDisplay(contentQuarterTurns: contentQuarterTurns),
    );
  }
}

class _ScanControlColumn extends StatelessWidget {
  const _ScanControlColumn({
    required this.showInlineModeSelector,
    required this.modeSelector,
    required this.dynamicContent,
  });

  final bool showInlineModeSelector;
  final Widget modeSelector;
  final Widget dynamicContent;

  @override
  Widget build(BuildContext context) {
    return _ScrollableContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showInlineModeSelector) ...[
            Center(child: modeSelector),
            const SizedBox(height: 24),
          ],
          dynamicContent,
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onModeChanged});

  final ScanningMode mode;
  final ValueChanged<ScanningMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    if (useCupertinoChrome) {
      return SizedBox(
        width: 240,
        child: AdaptiveSegmentedControl(
          labels: const ['Normal', 'Sender'],
          selectedIndex: ScanningMode.values.indexOf(mode),
          onValueChanged: (index) => onModeChanged(ScanningMode.values[index]),
        ),
      );
    }

    return SegmentedButton<ScanningMode>(
      segments: const [
        ButtonSegment(
          value: ScanningMode.normal,
          label: Text('Normal'),
          icon: Icon(Icons.person_pin_rounded),
        ),
        ButtonSegment(
          value: ScanningMode.sender,
          label: Text('Sender'),
          icon: Icon(Icons.send_rounded),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (newSelection) => onModeChanged(newSelection.first),
      showSelectedIcon: false,
    );
  }
}

class _DynamicScanContent extends StatelessWidget {
  const _DynamicScanContent({required this.mode, required this.activeInstance});

  final ScanningMode mode;
  final RemoteInstance? activeInstance;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: mode == ScanningMode.normal
            ? const CurrentScanResultPanel()
            : _SenderContent(activeInstance: activeInstance),
      ),
    );
  }
}

class _SenderContent extends StatelessWidget {
  const _SenderContent({required this.activeInstance});

  final RemoteInstance? activeInstance;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('SenderDetail'),
      children: [InstanceCard(activeInstance: activeInstance)],
    );
  }
}

class _ScrollableContent extends StatelessWidget {
  final Widget child;

  const _ScrollableContent({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomContentPadding =
        context.mediaQuery.padding.bottom + ScanPage._contentBottomSpacing;

    return Scrollbar(
      child: SingleChildScrollView(
        clipBehavior: Clip.none,
        padding: EdgeInsets.only(bottom: bottomContentPadding),
        child: child,
      ),
    );
  }
}
