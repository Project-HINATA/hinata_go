#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
scan_check_dir=$(mktemp -d)
trap 'rm -rf "$scan_check_dir"' EXIT
swiftc -parse-as-library ios/PrismClip/InvocationParser.swift ios/PrismClip/InvocationRouter.swift ios/PrismClip/Models.swift ios/PrismClip/PrismAPI.swift ios/PrismClip/MachineLoginViewModel.swift test/native/prism_visit_fixtures.swift test/native/prism_scan_check.swift -o "$scan_check_dir/check"
"$scan_check_dir/check"
