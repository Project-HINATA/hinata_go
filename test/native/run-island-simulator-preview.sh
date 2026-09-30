#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to a booted Dynamic Island iPhone simulator}"
output=${ISLAND_PREVIEW_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/hinata-island.XXXXXX")}
mkdir -p "$output"
xcodegen generate --spec "$root/test/native/island-preview/project.yml"
xcodebuild -project "$root/test/native/island-preview/IslandPreview.xcodeproj" \
  -scheme IslandPreview -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO -derivedDataPath "$output/Derived" \
  build-for-testing > "$output/build.log" 2>&1 || {
    tail -80 "$output/build.log"
    exit 1
  }
# Xcode may reuse an installed unsigned preview app after its debug dylib
# changes. Stop both disposable hosts and explicitly install the new bundles.
xcrun simctl terminate "$SIMULATOR_UDID" moe.neri.hinatago.timelinepreview >/dev/null 2>&1 || true
xcrun simctl terminate "$SIMULATOR_UDID" moe.neri.hinatago.timelinepreview.tests.xctrunner >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_UDID" "$output/Derived/Build/Products/Debug-iphonesimulator/IslandPreview.app"
xcrun simctl install "$SIMULATOR_UDID" "$output/Derived/Build/Products/Debug-iphonesimulator/IslandPreviewTests-Runner.app"
xcrun simctl launch "$SIMULATOR_UDID" moe.neri.hinatago.timelinepreview \
  -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN >/dev/null
set -- "$output"/Derived/Build/Products/*.xctestrun
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  printf 'Expected one generated xctestrun file in %s\n' "$output/Derived/Build/Products" >&2
  exit 1
fi
test_run=$1
if [ -n "${ISLAND_PREVIEW_TEST:-}" ]; then
  set -- "-only-testing:$ISLAND_PREVIEW_TEST"
else
  set --
fi
xcodebuild -xctestrun "$test_run" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath "$output/Preview.xcresult" "$@" test-without-building > "$output/test.log" 2>&1 || {
    tail -80 "$output/test.log"
    exit 1
  }
xcrun xcresulttool export attachments --path "$output/Preview.xcresult" --output-path "$output/screenshots"
printf 'Simulator screenshots and build log: %s\n' "$output"
