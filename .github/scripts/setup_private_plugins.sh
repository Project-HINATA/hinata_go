#!/usr/bin/env bash

set -euo pipefail

repo="${LOCAL_PLUGINS_REPO:-}"
token="${LOCAL_PLUGINS_TOKEN:-}"
ref="${LOCAL_PLUGINS_REF:-}"

if [[ -z "$repo" ]]; then
  echo "LOCAL_PLUGINS_REPO is empty, skipping private plugin setup."
  exit 0
fi

plugin_root="local_plugins"
plugin_path="${plugin_root}/hinata_firmware_feature"

/bin/mkdir -p "$plugin_root"

repo_url="$repo"
if [[ "$repo_url" =~ ^https://github.com/ ]]; then
  if [[ -n "$token" ]]; then
    repo_url="${repo_url/https:\/\/github.com\//https:\/\/x-access-token:${token}@github.com\/}"
  fi
elif [[ "$repo_url" =~ ^git@github.com: ]]; then
  repo_path="${repo_url#git@github.com:}"
  repo_path="${repo_path%.git}"
  repo_url="https://github.com/${repo_path}.git"
  if [[ -n "$token" ]]; then
    repo_url="https://x-access-token:${token}@github.com/${repo_path}.git"
  fi
elif [[ "$repo_url" != http* ]]; then
  repo_path="${repo_url%.git}"
  repo_url="https://github.com/${repo_path}.git"
  if [[ -n "$token" ]]; then
    repo_url="https://x-access-token:${token}@github.com/${repo_path}.git"
  fi
fi

if [[ -e "$plugin_path" ]]; then
  echo "$plugin_path already exists, skipping clone."
else
  if [[ -n "$ref" ]]; then
    git clone --depth 1 --branch "$ref" "$repo_url" "$plugin_path"
  else
    git clone --depth 1 "$repo_url" "$plugin_path"
  fi
fi

cat > pubspec_overrides.yaml <<'EOF'
dependency_overrides:
  hinata_firmware_feature:
    path: local_plugins/hinata_firmware_feature
EOF
