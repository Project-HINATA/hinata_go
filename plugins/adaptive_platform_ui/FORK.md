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
