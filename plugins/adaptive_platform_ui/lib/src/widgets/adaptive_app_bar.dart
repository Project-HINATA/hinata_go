import 'package:flutter/widgets.dart';
import '../toolbar/top_bar_accessory.dart';
import 'adaptive_app_bar_action.dart';

/// A leading control the native top bar can build itself, for pages whose
/// Flutter leading widget cannot be represented by UIKit.
enum NativeToolbarLeading { close }

/// Configuration for an adaptive app bar
///
/// This class holds the configuration for the app bar in [AdaptiveScaffold].
/// The actual rendering is platform-specific:
/// - iOS 26+ with useNativeToolbar: Native UIToolbar with Liquid Glass effects
/// - iOS 26+ without useNativeToolbar: CupertinoNavigationBar with custom back button
/// - iOS <26: CupertinoNavigationBar
/// - Android: Material AppBar
///
/// You can provide custom navigation bars using [cupertinoNavigationBar] or [appBar]:
/// - If [cupertinoNavigationBar] is provided and [useNativeToolbar] is false: Uses custom CupertinoNavigationBar on iOS
/// - If [appBar] is provided: Uses custom AppBar on Android
/// - Otherwise: Builds navigation bar from [title], [actions], and [leading]
class AdaptiveAppBar {
  /// Creates an adaptive app bar configuration
  const AdaptiveAppBar({
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.useNativeToolbar = true,
    this.tintColor,
    this.titleWidget,
    this.nativeLogo = false,
    this.largeTitle = false,
    this.chips,
    this.nativeLeading,
    this.onNativeLeadingTap,
    this.cupertinoNavigationBar,
    this.appBar,
  });

  /// Title for the app bar
  final String? title;

  /// Optional subtitle displayed below the title
  final String? subtitle;

  /// Action buttons in the app bar
  /// - iOS 26+ with native toolbar: Rendered as native UIBarButtonItem in UIToolbar
  /// - iOS < 26: Rendered as buttons in CupertinoNavigationBar
  /// - Android: Rendered as IconButtons in Material AppBar
  final List<AdaptiveAppBarAction>? actions;

  /// Leading widget in the app bar (e.g., back button, menu button)
  /// If null and navigation is possible, an automatic back button will be shown
  final Widget? leading;

  /// Use native iOS 26 toolbar (iOS 26+ only)
  /// - When false (default): Uses CupertinoNavigationBar for better compatibility with routers
  /// - When true: Uses native iOS 26 UIToolbar with Liquid Glass effect
  ///
  /// Note: Setting this to true may cause compatibility issues with GoRouter and other
  /// router packages. Use with caution.
  ///
  /// If true, [cupertinoNavigationBar] will be ignored and native toolbar will be shown.
  final bool useNativeToolbar;

  /// Custom widget to display in the title area
  ///
  /// When set, this widget replaces the default title text rendering.
  /// On iOS 26+ with native toolbar, it is overlaid centered over the toolbar.
  /// On iOS < 26, it is used as the CupertinoNavigationBar middle.
  /// On Android, it is used as the AppBar title.
  final Widget? titleWidget;

  /// Tint color for toolbar action buttons (iOS 26+ native toolbar only)
  ///
  /// When set, this color is applied to the navigation bar's tintColor,
  /// which colors all bar button items (action buttons and back button).
  /// If null, the system default tint color is used.
  final Color? tintColor;

  /// Whether the native bar should show the app logo next to [title].
  final bool nativeLogo;

  /// Show the title large at the top of the page while its content is
  /// scrolled to the top, the way UIKit large titles do, and hand it to the
  /// bar as a small centred title once the content scrolls under the bar.
  ///
  /// Only takes effect where the native UIKit top bar is horizontal (iOS 26+
  /// with [AdaptiveToolbarHost.nativeTopBar]); the page's main vertical
  /// scroll view drives it.
  final bool largeTitle;

  /// Chips the native top bar shows as a strip of Liquid Glass capsules under
  /// itself (below the large title), such as folders or filters. They stay
  /// on screen while the content scrolls beneath them.
  ///
  /// Only the native UIKit top bar draws them; check
  /// [TopBarAccessoryScope.isNative] in the page and draw a selector of its
  /// own where it is false.
  final List<AdaptiveToolbarChip>? chips;

  /// A leading control for the native top bar. When null, the native bar
  /// falls back to an automatic back button or no leading.
  final NativeToolbarLeading? nativeLeading;

  /// Invoked when the native leading control is tapped.
  final VoidCallback? onNativeLeadingTap;

  /// Custom CupertinoNavigationBar for iOS
  ///
  /// When provided and [useNativeToolbar] is false, this custom navigation bar will be used
  /// instead of building one from [title], [actions], and [leading].
  ///
  /// Ignored when [useNativeToolbar] is true or on non-iOS platforms.
  final PreferredSizeWidget? cupertinoNavigationBar;

  /// Custom AppBar for Android
  ///
  /// When provided, this custom app bar will be used instead of building one
  /// from [title], [actions], and [leading].
  ///
  /// Ignored on iOS platforms.
  final PreferredSizeWidget? appBar;

  /// Creates a copy of this app bar with the given fields replaced
  AdaptiveAppBar copyWith({
    String? title,
    String? subtitle,
    List<AdaptiveAppBarAction>? actions,
    Widget? leading,
    bool? useNativeToolbar,
    Color? tintColor,
    Widget? titleWidget,
    bool? nativeLogo,
    bool? largeTitle,
    List<AdaptiveToolbarChip>? chips,
    NativeToolbarLeading? nativeLeading,
    VoidCallback? onNativeLeadingTap,
    PreferredSizeWidget? cupertinoNavigationBar,
    PreferredSizeWidget? appBar,
  }) {
    return AdaptiveAppBar(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      actions: actions ?? this.actions,
      leading: leading ?? this.leading,
      useNativeToolbar: useNativeToolbar ?? this.useNativeToolbar,
      tintColor: tintColor ?? this.tintColor,
      titleWidget: titleWidget ?? this.titleWidget,
      nativeLogo: nativeLogo ?? this.nativeLogo,
      largeTitle: largeTitle ?? this.largeTitle,
      chips: chips ?? this.chips,
      nativeLeading: nativeLeading ?? this.nativeLeading,
      onNativeLeadingTap: onNativeLeadingTap ?? this.onNativeLeadingTap,
      cupertinoNavigationBar:
          cupertinoNavigationBar ?? this.cupertinoNavigationBar,
      appBar: appBar ?? this.appBar,
    );
  }
}
