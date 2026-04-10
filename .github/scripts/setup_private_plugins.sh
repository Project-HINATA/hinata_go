#!/usr/bin/env bash

set -euo pipefail

repo="${LOCAL_PLUGINS_REPO:-}"
token="${LOCAL_PLUGINS_TOKEN:-}"
ref="${LOCAL_PLUGINS_REF:-}"
cardcipher_repo="${CARDCIPHER_REPO:-}"
cardcipher_token="${CARDCIPHER_TOKEN:-}"
cardcipher_ref="${CARDCIPHER_REF:-}"

plugin_root="local_plugins"

/bin/mkdir -p "$plugin_root"

if [[ -z "$repo" && -z "$cardcipher_repo" ]]; then
  echo "No private plugin repositories configured, skipping setup."
  exit 0
fi

normalize_repo_url() {
  local input_repo="$1"
  local input_token="$2"
  local repo_url="$input_repo"

  if [[ "$repo_url" =~ ^https://github.com/ ]]; then
    if [[ -n "$input_token" ]]; then
      repo_url="${repo_url/https:\/\/github.com\//https:\/\/x-access-token:${input_token}@github.com\/}"
    fi
  elif [[ "$repo_url" =~ ^git@github.com: ]]; then
    local repo_path="${repo_url#git@github.com:}"
    repo_path="${repo_path%.git}"
    repo_url="https://github.com/${repo_path}.git"
    if [[ -n "$input_token" ]]; then
      repo_url="https://x-access-token:${input_token}@github.com/${repo_path}.git"
    fi
  elif [[ "$repo_url" != http* ]]; then
    local repo_path="${repo_url%.git}"
    repo_url="https://github.com/${repo_path}.git"
    if [[ -n "$input_token" ]]; then
      repo_url="https://x-access-token:${input_token}@github.com/${repo_path}.git"
    fi
  fi

  printf '%s\n' "$repo_url"
}

clone_plugin() {
  local input_repo="$1"
  local input_token="$2"
  local input_ref="$3"
  local plugin_path="$4"

  if [[ -z "$input_repo" ]]; then
    return
  fi

  local repo_url
  repo_url="$(normalize_repo_url "$input_repo" "$input_token")"

  if [[ -e "$plugin_path" ]]; then
    echo "$plugin_path already exists, skipping clone."
  fi

  if [[ ! -e "$plugin_path" ]]; then
    if [[ -n "$input_ref" ]]; then
      git clone --depth 1 --branch "$input_ref" "$repo_url" "$plugin_path"
    else
      git clone --depth 1 "$repo_url" "$plugin_path"
    fi
  fi

  local override_name
  override_name="$(basename "$plugin_path")"
  override_lines+=("  ${override_name}:")
  override_lines+=("    path: ${plugin_path}")
}

declare -a override_lines=("dependency_overrides:")

clone_plugin \
  "$repo" \
  "$token" \
  "$ref" \
  "${plugin_root}/hinata_firmware_feature"
clone_plugin \
  "$cardcipher_repo" \
  "$cardcipher_token" \
  "$cardcipher_ref" \
  "${plugin_root}/cardcipher"

if [[ "${#override_lines[@]}" -eq 1 ]]; then
  echo "No private plugin overrides were generated."
  exit 0
fi

{
  for line in "${override_lines[@]}"; do
    printf '%s\n' "$line"
  done
} > pubspec_overrides.yaml
