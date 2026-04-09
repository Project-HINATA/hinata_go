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

if [[ "$pub_ver" == "$clean_latest" ]]; then
  new_tag="pre-${pub_ver}-${commit_short}"
  title="Pre-release ${pub_ver} (${commit_short})"
else
  new_tag="v${pub_ver}"
  title="Release v${pub_ver}"
  is_prerelease=false

  if [[ -n "$latest_tag" ]]; then
    logs="$(git log "$latest_tag..HEAD" --oneline | grep -E '^[a-f0-9]+ (feat|fix|ui):' || echo '无特定变更记录')"
  else
    logs="$(git log --oneline | grep -E '^[a-f0-9]+ (feat|fix|ui):' || echo '首次发布')"
  fi
  changelog="### 🚀 更新内容"$'\n'"$logs"
fi

echo "tag_name=$new_tag" >> "$GITHUB_OUTPUT"
echo "mode_title=$title" >> "$GITHUB_OUTPUT"
echo "is_prerelease=$is_prerelease" >> "$GITHUB_OUTPUT"
{
  echo "changelog<<EOF"
  echo -e "$changelog"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
