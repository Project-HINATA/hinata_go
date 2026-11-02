#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "GITHUB_OUTPUT is not set."
  exit 1
fi

pub_ver="$(grep '^version:' pubspec.yaml | sed 's/version://' | tr -d ' "' | cut -d'+' -f1 | tr -d '\r')"
commit_short="$(git rev-parse --short HEAD | tr -d '\r')"

latest_tag="$(gh release list --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo '')"
clean_latest="$(echo "${latest_tag#v}" | tr -d '\r')"

changelog="自动构建产物"
is_prerelease=true
play_notes_dir=""

if [[ "$pub_ver" == "$clean_latest" ]]; then
  # Pre-releases always reuse the single rolling "pre" tag so the release
  # list never accumulates one entry per build; the commit lives in the
  # title and body instead.
  new_tag="pre"
  title="Pre-release ${pub_ver} (${commit_short})"
else
  new_tag="v${pub_ver}"
  title="Release v${pub_ver}"
  is_prerelease=false

  notes_dir="${RUNNER_TEMP:-$(mktemp -d)}/release-notes"
  ./.github/scripts/generate_release_notes.sh "$pub_ver" "$notes_dir"

  if [[ "$(cat "$notes_dir/found")" == "true" ]]; then
    changelog="### 🚀 更新内容"$'\n\n'"$(cat "$notes_dir/zh.md")"$'\n\n'"### 🚀 What's New"$'\n\n'"$(cat "$notes_dir/en.md")"
  else
    if [[ -n "$latest_tag" ]]; then
      logs="$(git log "$latest_tag..HEAD" --oneline | grep -E '^[a-f0-9]+ (feat|fix|ui):' || echo '无特定变更记录')"
    else
      logs="$(git log --oneline | grep -E '^[a-f0-9]+ (feat|fix|ui):' || echo '首次发布')"
    fi
    changelog="### 🚀 更新内容"$'\n'"$logs"
  fi

  # Google Play reads one whatsnew-<locale> file per language.
  play_notes_dir="${notes_dir}/play"
  mkdir -p "$play_notes_dir"
  cp "$notes_dir/zh_short.txt" "$play_notes_dir/whatsnew-zh-CN"
  cp "$notes_dir/en_short.txt" "$play_notes_dir/whatsnew-en-US"
fi

echo "tag_name=$new_tag" >> "$GITHUB_OUTPUT"
echo "mode_title=$title" >> "$GITHUB_OUTPUT"
echo "is_prerelease=$is_prerelease" >> "$GITHUB_OUTPUT"
echo "play_notes_dir=$play_notes_dir" >> "$GITHUB_OUTPUT"
{
  echo "changelog<<EOF"
  printf '%s\n' "$changelog"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
