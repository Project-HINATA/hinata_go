#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
prism_core_dir=$(mktemp -d)
trap 'rm -rf "$prism_core_dir"' EXIT
swiftc -swift-version 5 -parse-as-library ios/PrismCore/*.swift test/native/prism_core_check.swift -o "$prism_core_dir/prism-core-check"
"$prism_core_dir/prism-core-check" test/native/fixtures/prism-core
