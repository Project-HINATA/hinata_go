# Vendored fork of adaptive_platform_ui 1.0.2

Upstream: https://github.com/berkaycatak/adaptive_platform_ui (MIT, see LICENSE).
The `example/` and `img/` directories are not vendored.

Changes from upstream:

- **Web and desktop render Material.** Widgets used to fall back to Cupertino on
  every platform that is neither iOS nor Android. They now check
  `PlatformInfo.usesMaterial` (everything except iOS), so web looks exactly like
  Android.
- **`ToolbarChromeScope` is exported**, so an app can tell when the iPhone Duo
  vertical bar hosts the tab bar and the bottom edge stays free.
- **Custom toolbar titles get the system title style.** `titleWidget` in the
  fixed iOS 26 toolbar and in the iPhone Duo title band used to render without a
  `DefaultTextStyle` (Flutter's red fallback text).
- **The Duo glass capsule is shaped by `cornerConfiguration` on iOS 26**, not
  only by `layer.cornerRadius`, so a resize while the device folds cannot leave
  it looking square for a frame. Corner-radius writes are also unanimated.
- **Covered chrome is disarmed natively.** `IgnorePointer` does not stop the
  native buttons inside a platform view, so the Duo capsules and the native
  toolbar now carry an `interactive` flag that disables touches in UIKit while
  a dialog or sheet covers the page.
- **iOS 26 alerts keep their native Liquid Glass.** The old code inserted a
  thin-material blur behind the alert, which hid the system material and left
  the alert looking solid; that fallback now only runs before iOS 26.
