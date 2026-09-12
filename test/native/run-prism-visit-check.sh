#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_check_dir=$(mktemp -d)
trap 'rm -rf "$prism_check_dir"' EXIT
swiftc -parse-as-library ios/PrismClip/InvocationParser.swift ios/PrismClip/Models.swift ios/PrismClip/PrismAPI.swift ios/PrismClip/MachineLoginViewModel.swift test/native/prism_visit_check.swift -o "$prism_check_dir/prism-visit-check"
"$prism_check_dir/prism-visit-check"
