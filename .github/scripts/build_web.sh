#!/usr/bin/env bash

set -euo pipefail

build_id="${CF_PAGES_COMMIT_SHA:-$(git rev-parse HEAD)}"
build_id="${build_id:0:12}"

if [[ ! "$build_id" =~ ^[0-9a-fA-F]{7,12}$ ]]; then
  echo "Invalid web build ID: $build_id"
  exit 1
fi

flutter build web --release --wasm

runtime_dir="build/web/runtime/$build_id"
mkdir -p "$runtime_dir"
cp -R build/web/canvaskit "$runtime_dir/canvaskit"

for file in build/web/index.html build/web/flutter_bootstrap.js; do
  sed "s/__WEB_BUILD_ID__/$build_id/g" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
done
