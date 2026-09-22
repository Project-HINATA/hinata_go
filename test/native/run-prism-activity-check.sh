#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
activity_check_dir=$(mktemp -d)
trap 'rm -rf "$activity_check_dir"' EXIT
# Only the ActivityKit protocol is unavailable on macOS; exercise the real Codable model.
{ printf '%s\n' 'protocol ActivityAttributes { associatedtype ContentState: Codable, Hashable }'; sed '/^import ActivityKit$/d' ios/LiveActivityShared/StoreVisitAttributes.swift; } > "$activity_check_dir/Attributes.swift"
swiftc -parse-as-library "$activity_check_dir/Attributes.swift" test/native/prism_activity_check.swift -o "$activity_check_dir/check"
"$activity_check_dir/check"
