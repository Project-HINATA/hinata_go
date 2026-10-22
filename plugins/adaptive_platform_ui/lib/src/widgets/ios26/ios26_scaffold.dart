import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../style/sf_symbol.dart';
import '../../toolbar/toolbar_chrome_scope.dart';
import '../../toolbar/top_bar_accessory.dart';
import '../adaptive_app_bar_action.dart';
import '../adaptive_button.dart';
import 'ios26_native_toolbar.dart';

/// Height of the iOS 26 Liquid Glass toolbar's content area (excluding the
/// status bar), matching [IOS26NativeToolbar]'s default height. The toolbar is
/// an overlay, so this amount is added to the body's top padding.
const double kToolbarContentHeight = 44.0;

/// An iOS 26 page.
///
/// Under an [AdaptiveToolbarHost] whose native UIKit bar owns the top bar,
/// the page only publishes its items (see [AdaptiveScaffold]) and lays its
/// body out for that bar: the large title and the chip strip below it, and
/// the side insets. Anywhere else (a dialog, a sheet, an app without the
/// native shell) it draws its own Liquid Glass toolbar.
class IOS26Scaffold extends StatefulWidget {
  const IOS26Scaffold({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.tintColor,
    this.titleWidget,
    this.useHeroBackButton = true,
    this.useFixedToolbar = true,
    this.resizeToAvoidBottomInset,
    this.backgroundColor,
    this.largeTitle,
    this.scrollOffset,
    this.accessory = false,
    required this.body,
  });

  final String? title;
  final List<AdaptiveAppBarAction>? actions;
  final Widget? leading;
  final Color? tintColor;

  /// Custom widget overlaid at the toolbar's title position.
  /// When set, the native title is hidden and this widget is centered instead.
  final Widget? titleWidget;
  final bool useHeroBackButton;

  /// Whether the fixed toolbar host, when there is one, draws this page's
  /// toolbar. False makes the page draw its own, as it does without a host.
  final bool useFixedToolbar;

  /// Page background; null keeps the Cupertino theme's scaffold colour.
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final Widget body;

  /// The page title drawn large above the content while the native UIKit bar
  /// owns the top bar. The body is inset by [kLargeTitleHeight] below the bar
  /// and the title moves with [scrollOffset], so it scrolls away under the
  /// bar together with the content.
  final Widget? largeTitle;

  /// How far the body's main vertical scroll view is scrolled.
  final ValueListenable<double>? scrollOffset;

  /// Whether the app bar has chips, which the native UIKit top bar shows in
  /// a strip under itself. The body is inset by [kTopBarAccessoryHeight] for
  /// it, below the large title.
  final bool accessory;

  @override
  State<IOS26Scaffold> createState() => _IOS26ScaffoldState();
}

class _IOS26ScaffoldState extends State<IOS26Scaffold> {
  /// Determines if the current window is in a windowed mode.
  ///
  /// This method compares the display size of the device with the viewport size
  /// calculated from the logical size and device pixel ratio.
  /// It returns true if the sizes do not match, indicating that the application is not in full-screen mode.
  bool _getIsWindowed() {
    final displaySize = View.of(context).display.size;
    final logicalSize = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final viewportSize = Size(
      logicalSize.width * devicePixelRatio,
      logicalSize.height * devicePixelRatio,
    );

    return (displaySize.longestSide != viewportSize.longestSide) ||
        (displaySize.shortestSide != viewportSize.shortestSide);
  }

  @override
  Widget build(BuildContext context) {
    // Auto back button logic
    // Priority: custom leading widget > Hero back button
    Widget? heroLeading;

    final canPop = Navigator.of(context).canPop();

    // Only show auto back button if no custom leading widget
    if (widget.leading == null && canPop) {
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrent) {
        final backButton = Container(
          // 62px accounts for the iPadOS system window toolbar width in windowed mode
          margin: EdgeInsets.only(left: _getIsWindowed() ? 62 : 0),
          height: 38,
          width: 38,
          child: AdaptiveButton.sfSymbol(
            onPressed: () => Navigator.of(context).pop(),
            sfSymbol: SFSymbol("chevron.left", size: 20),
            useSmoothRectangleBorder: false,
          ),
        );
        heroLeading = widget.useHeroBackButton
            ? Hero(
                tag: 'adaptive_back_button',
                flightShuttleBuilder: (_, _, _, _, toHeroContext) =>
                    toHeroContext.widget,
                child: backButton,
              )
            : backButton;
      } else {
        const placeholder = SizedBox(height: 38, width: 38);
        heroLeading = widget.useHeroBackButton
            ? const Hero(tag: 'adaptive_back_button', child: placeholder)
            : placeholder;
      }
    }

    // Determine if toolbar's underlying UiKitView should be shown.
    // Hide native platform views when another route is pushed on top to prevent bleed-through.
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final isPopping =
        ModalRoute.of(context)?.animation?.status == AnimationStatus.reverse;

    // The Flutter widgets (like Hero) should ALWAYS stay in the tree during transitions.
    // Only the underlying UiKitView should be hidden.
    final hasToolbarContent =
        (widget.title != null ||
        widget.titleWidget != null ||
        widget.leading != null ||
        heroLeading != null ||
        (widget.actions != null && widget.actions!.isNotEmpty));

    // Show native view only if it's the current route OR it's popping
    final showNativeView = isCurrentRoute || isPopping;

    // Get brightness and determine text color
    final brightness = MediaQuery.platformBrightnessOf(context);
    final textColor = brightness == Brightness.dark
        ? CupertinoColors.white
        : CupertinoColors.black;

    // Wrap content with DefaultTextStyle to ensure proper text color
    Widget bodyContent = DefaultTextStyle(
      style: TextStyle(
        color: textColor,
        fontSize: 17, // iOS default
      ),
      child: widget.body,
    );

    final chrome = widget.useFixedToolbar
        ? ToolbarChromeScope.maybeOf(context)
        : null;
    final mq = MediaQuery.of(context);
    final nativeTopBarOwned = chrome?.nativeTopBarOwned ?? false;
    final showTopToolbar = !nativeTopBarOwned && hasToolbarContent;

    // A large title only exists where the native bar shows its small title
    // once this one has scrolled under it; the native shell says where.
    final largeTitle = widget.largeTitle;
    final scrollOffset = widget.scrollOffset;
    final largeTitles = nativeTopBarOwned && (chrome?.largeTitles ?? false);
    final showLargeTitle =
        largeTitle != null && scrollOffset != null && largeTitles;
    // The native chip strip has the same constraint.
    final showAccessory = widget.accessory && largeTitles;

    // The Liquid Glass toolbar this page draws, and the large title and the
    // chips below the native bar, overlay the body; like a translucent bar
    // they are added to the body's top inset, so SafeArea and scroll views in
    // the page start their content below them while the content still scrolls
    // up underneath them.
    //
    // Under the native bar the body is also kept within the side safe area,
    // as UIKit keeps a page's content: clear of the notch in landscape and of
    // the iPhone Duo vertical bar. The side insets are consumed, so a SafeArea
    // further down has nothing left to add.
    final topInset =
        (showTopToolbar ? kToolbarContentHeight : 0.0) +
        (showLargeTitle ? kLargeTitleHeight : 0.0) +
        (showAccessory ? kTopBarAccessoryHeight : 0.0);
    final sides = nativeTopBarOwned
        ? EdgeInsets.only(left: mq.padding.left, right: mq.padding.right)
        : EdgeInsets.zero;
    if (topInset > 0 || sides != EdgeInsets.zero) {
      // One MediaQuery for every inset: a second one nested inside it would
      // replace this one's padding rather than add to it.
      bodyContent = Padding(
        padding: sides,
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              top: mq.padding.top + topInset,
              left: mq.padding.left - sides.left,
              right: mq.padding.right - sides.right,
            ),
            viewPadding: mq.viewPadding.copyWith(
              top: mq.viewPadding.top + topInset,
            ),
          ),
          child: showAccessory
              ? TopBarAccessoryScope(child: bodyContent)
              : bodyContent,
        ),
      );
    }

    // Lined up with the bar's own title margin.
    final titleMargin = chrome?.largeTitleMargin ?? 16;

    return CupertinoPageScaffold(
      backgroundColor: widget.backgroundColor,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset ?? true,
      child: Stack(
        children: [
          bodyContent,
          if (showLargeTitle)
            Positioned(
              top: mq.padding.top,
              left: 0,
              right: 0,
              height: kLargeTitleHeight,
              child: _LargeTitle(
                offset: scrollOffset,
                padding: EdgeInsets.only(
                  left: mq.padding.left + titleMargin,
                  right: mq.padding.right + titleMargin,
                  // Puts the baseline where UIKit puts its large title's.
                  bottom: 6,
                ),
                color: textColor,
                child: largeTitle,
              ),
            ),
          if (showTopToolbar)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IOS26NativeToolbar(
                title: widget.title,
                leading: widget.leading ?? heroLeading,
                showNativeView: showNativeView,
                actions: widget.actions,
                tintColor: widget.tintColor,
                titleWidget: widget.titleWidget,
                onActionTap: (index) {
                  if (widget.actions != null &&
                      index >= 0 &&
                      index < widget.actions!.length) {
                    widget.actions![index].onPressed();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The large title band below the native bar.
///
/// It follows the page's scroll offset by repainting with a translation, so a
/// scroll frame neither rebuilds nor lays out the title again. It moves up
/// under the clear bar whole, and once all of it is there, where the bar
/// takes over with its glass and small title, it fades out.
class _LargeTitle extends StatefulWidget {
  const _LargeTitle({
    required this.offset,
    required this.padding,
    required this.color,
    required this.child,
  });

  final ValueListenable<double> offset;
  final EdgeInsets padding;
  final Color color;
  final Widget child;

  @override
  State<_LargeTitle> createState() => _LargeTitleState();
}

class _LargeTitleState extends State<_LargeTitle>
    with SingleTickerProviderStateMixin {
  /// 1 while the title is shown; same fade as the bar's small title.
  late final AnimationController _visibility = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: _collapsed ? 0 : 1,
  );

  bool get _collapsed => widget.offset.value >= kLargeTitleCollapseOffset;

  @override
  void initState() {
    super.initState();
    widget.offset.addListener(_onOffsetChanged);
  }

  @override
  void didUpdateWidget(_LargeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.offset, widget.offset)) {
      oldWidget.offset.removeListener(_onOffsetChanged);
      widget.offset.addListener(_onOffsetChanged);
      _visibility.value = _collapsed ? 0 : 1;
    }
  }

  void _onOffsetChanged() {
    if (_collapsed) {
      _visibility.reverse();
    } else {
      _visibility.forward();
    }
  }

  @override
  void dispose() {
    widget.offset.removeListener(_onOffsetChanged);
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final style = CupertinoTheme.of(
      context,
    ).textTheme.navLargeTitleTextStyle.copyWith(color: color);
    return IgnorePointer(
      child: Flow(
        delegate: _ScrollFollowingFlow(widget.offset, _visibility),
        // The title moves up out of its band, under the bar.
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: widget.padding,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Semantics(
                header: true,
                // The band has the fixed height of UIKit's large title, so the
                // title keeps its size at larger text settings instead of
                // overflowing it.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1,
                  child: IconTheme.merge(
                    data: IconThemeData(size: style.fontSize, color: color),
                    child: DefaultTextStyle(
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollFollowingFlow extends FlowDelegate {
  _ScrollFollowingFlow(this.offset, this.visibility)
    : super(repaint: Listenable.merge([offset, visibility]));

  final ValueListenable<double> offset;
  final Animation<double> visibility;

  @override
  void paintChildren(FlowPaintingContext context) {
    if (visibility.value == 0) return;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(0, -offset.value, 0),
      opacity: visibility.value,
    );
  }

  @override
  bool shouldRepaint(_ScrollFollowingFlow oldDelegate) =>
      !identical(oldDelegate.offset, offset) ||
      !identical(oldDelegate.visibility, visibility);
}
