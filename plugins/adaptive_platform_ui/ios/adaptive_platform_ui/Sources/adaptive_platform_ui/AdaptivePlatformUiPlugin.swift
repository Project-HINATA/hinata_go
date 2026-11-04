import Flutter
import UIKit

/// Main plugin class for Adaptive Platform UI
/// Registers platform views and handles plugin lifecycle
public class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register iOS 26 Button platform view factory
        let ios26ButtonFactory = iOS26ButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ButtonFactory,
            withId: "adaptive_platform_ui/ios26_button"
        )

        // Register iOS 26 Switch platform view factory
        let ios26SwitchFactory = iOS26SwitchViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SwitchFactory,
            withId: "adaptive_platform_ui/ios26_switch"
        )

        // Register iOS 26 Slider platform view factory
        let ios26SliderFactory = iOS26SliderViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SliderFactory,
            withId: "adaptive_platform_ui/ios26_slider"
        )

        // Register iOS 26 SegmentedControl platform view factory
        let ios26SegmentedControlFactory = iOS26SegmentedControlViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SegmentedControlFactory,
            withId: "adaptive_platform_ui/ios26_segmented_control"
        )

        // Register iOS 26 AlertDialog platform view factory
        let ios26AlertDialogFactory = iOS26AlertDialogViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26AlertDialogFactory,
            withId: "adaptive_platform_ui/ios26_alert_dialog"
        )

        // Register iOS 26 PopupMenuButton platform view factory
        let ios26PopupMenuButtonFactory = iOS26PopupMenuButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26PopupMenuButtonFactory,
            withId: "adaptive_platform_ui/ios26_popup_menu_button"
        )

        // Register iOS 26 ContextMenu platform view factory
        let ios26ContextMenuFactory = iOS26ContextMenuViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ContextMenuFactory,
            withId: "adaptive_platform_ui/ios26_context_menu"
        )

        // Register iOS 26 Toolbar platform view factory
        let ios26ToolbarFactory = iOS26ToolbarFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ToolbarFactory,
            withId: "adaptive_platform_ui/ios26_toolbar"
        )

        // Register iOS 26 Blur View platform view factory
        let ios26BlurViewFactory = iOS26BlurViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26BlurViewFactory,
            withId: "adaptive_platform_ui/ios26_blur_view"
        )
    }
}

/// Keeps the display at its full refresh rate while a Liquid Glass control
/// animates: appearing with its page, pressed, or moving its selection.
///
/// Glass animations ask for 80 Hz, and Flutter's frame timer accepts any rate
/// from 60 Hz up, so the whole screen, Flutter included, would drop to 80 Hz
/// and switch back mid-animation. This display link asks for the full rate
/// and nothing lower for a moment; it stops on its own afterwards.
enum GlassFrameRate {
    private static var link: CADisplayLink?
    private static var until: CFTimeInterval = 0
    private static let target = GlassFrameRateTarget()

    static func hold(for duration: CFTimeInterval = 0.8) {
        until = max(until, CACurrentMediaTime() + duration)
        guard link == nil else { return }
        let rate = Float(UIScreen.main.maximumFramesPerSecond)
        let link = CADisplayLink(target: target, selector: #selector(GlassFrameRateTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        }
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate static func tick(_ link: CADisplayLink) {
        guard link.timestamp >= until else { return }
        link.invalidate()
        self.link = nil
    }
}

private final class GlassFrameRateTarget: NSObject {
    @objc func tick(_ link: CADisplayLink) { GlassFrameRate.tick(link) }
}
