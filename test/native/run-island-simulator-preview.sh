#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to a booted Dynamic Island iPhone simulator}"
output=${ISLAND_PREVIEW_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/hinata-island.XXXXXX")}
mkdir -p "$output"
xcodegen generate --spec "$root/test/native/island-preview/project.yml"
if [ -n "${ISLAND_PREVIEW_TEST:-}" ]; then
  set -- "-only-testing:$ISLAND_PREVIEW_TEST"
else
  set --
fi
xcodebuild -project "$root/test/native/island-preview/IslandPreview.xcodeproj" \
  -scheme IslandPreview -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO -derivedDataPath "$output/Derived" \
  -resultBundlePath "$output/Preview.xcresult" "$@" test > "$output/build.log" 2>&1 || {
    tail -80 "$output/build.log"
    exit 1
  }
xcrun xcresulttool export attachments --path "$output/Preview.xcresult" --output-path "$output/screenshots"
printf 'Simulator screenshots and build log: %s\n' "$output"
