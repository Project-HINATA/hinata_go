#!/bin/bash
set -euo pipefail

: "${IOS_BUILD_NAME:?}"
: "${IOS_BUILD_NUMBER:?}"
: "${IOS_ASC_KEY_ID:?}"
: "${IOS_ASC_ISSUER_ID:?}"
: "${IOS_ASC_KEY_P8_BASE64:?}"
: "${RUNNER_TEMP:?}"
: "${GITHUB_SHA:?}"

# Reuse the CI's existing ASC key for provisioning as well as upload.
# Never print the key, and remove its temporary copy even on build failure.
umask 077
signing_key_path="$(mktemp "$RUNNER_TEMP/hinata-asc-key.XXXXXX")"
trap 'unlink "$signing_key_path"' EXIT
printf '%s' "$IOS_ASC_KEY_P8_BASE64" | base64 --decode > "$signing_key_path"
signing_args=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$signing_key_path"
  -authenticationKeyID "$IOS_ASC_KEY_ID"
  -authenticationKeyIssuerID "$IOS_ASC_ISSUER_ID"
)

flutter build ios --release --config-only \
  --build-name="$IOS_BUILD_NAME" \
  --build-number="$IOS_BUILD_NUMBER" \
  --dart-define=GIT_COMMIT_HASH="$GITHUB_SHA" \
  --split-debug-info=build/symbols \
  --obfuscate

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive \
  "${signing_args[@]}" archive

app_path=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
clip_path="$app_path/AppClips/PRiSM Link.app"
test -d "$clip_path"
for plist_key in CFBundleShortVersionString CFBundleVersion; do
  app_version="$(/usr/libexec/PlistBuddy -c "Print :$plist_key" "$app_path/Info.plist")"
  clip_version="$(/usr/libexec/PlistBuddy -c "Print :$plist_key" "$clip_path/Info.plist")"
  if [[ "$app_version" != "$clip_version" ]]; then
    echo "App Clip $plist_key does not match parent app" >&2
    exit 1
  fi
done

fastlane ios prepare_distribution_profiles

xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist \
  "${signing_args[@]}"
