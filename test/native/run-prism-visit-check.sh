#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_check_dir=$(mktemp -d)
trap 'rm -rf "$prism_check_dir"' EXIT
swiftc -parse-as-library ios/ArcadeLinkClip/InvocationParser.swift ios/ArcadeLinkClip/Models.swift ios/ArcadeLinkClip/ArcadeLinkAPI.swift ios/ArcadeLinkClip/MachineLoginViewModel.swift test/native/prism_visit_check.swift -o "$prism_check_dir/prism-visit-check"
"$prism_check_dir/prism-visit-check"
