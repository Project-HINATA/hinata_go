#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_check_dir=$(mktemp -d)
trap 'rm -rf "$prism_check_dir"' EXIT
swiftc -parse-as-library ios/PrismClip/Models.swift test/native/prism_time_check.swift -o "$prism_check_dir/prism-time-check"
"$prism_check_dir/prism-time-check"
