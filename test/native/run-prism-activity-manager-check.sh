#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
activity_check_dir=$(mktemp -d)
trap 'rm -rf "$activity_check_dir"' EXIT
# Compile the real manager and model; only the OS activity and network boundaries are mocked.
sed '/^import ActivityKit$/d' ios/LiveActivityShared/StoreVisitAttributes.swift > "$activity_check_dir/Attributes.swift"
sed '/^import ActivityKit$/d' ios/LiveActivityShared/StoreVisitLiveActivityManager.swift > "$activity_check_dir/Manager.swift"
swiftc -parse-as-library "$activity_check_dir/Attributes.swift" "$activity_check_dir/Manager.swift" ios/PrismClip/Models.swift test/native/prism_activity_manager_check.swift -o "$activity_check_dir/check"
"$activity_check_dir/check"
