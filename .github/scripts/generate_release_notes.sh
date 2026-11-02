#!/usr/bin/env bash
#
# Writes the release notes for <version> into <out_dir>, taken from the
# version's entry in CHANGELOG.md:
#
#   ## <version> - <YYYY-MM-DD>
#
#   ### 中文
#   ...
#
#   ### English
#   ...
#
# Files written:
#   zh.md, en.md                markdown as written (GitHub Release)
#   zh.txt, en.txt              plain text, at most 4000 characters (App Store)
#   zh_short.txt, en_short.txt  plain text, at most 500 characters (Google Play)
#   found                       "true" when CHANGELOG.md has the version
#
# Without an entry for the version, a generic text is written and the
# release goes on with a warning.
#
# Usage: generate_release_notes.sh <version> <out_dir>

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version> <out_dir>" >&2
  exit 2
fi

version="$1"
out_dir="$2"
mkdir -p "$out_dir"

python3 - "$version" "$out_dir" CHANGELOG.md <<'PY'
import os
import re
import sys

version, out_dir, path = sys.argv[1:4]


def write(name, text):
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as file:
        file.write(text.rstrip("\n") + "\n")


def plain(markdown):
    lines = []
    for line in markdown.splitlines():
        line = re.sub(r"^(\s*)[-*]\s+", lambda m: m.group(1) + "• ", line)
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
        line = re.sub(r"`([^`]+)`", r"\1", line)
        line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", line)
        line = re.sub(r"<(https?://[^>\s]+)>", r"\1", line)
        lines.append(line.rstrip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def clip(text, limit):
    # Cut at the last whole line that fits.
    if len(text) <= limit:
        return text
    kept = ""
    for line in text.splitlines():
        candidate = f"{kept}\n{line}" if kept else line
        if len(candidate) + 2 > limit:
            break
        kept = candidate
    return (kept or text[: limit - 2]) + "\n…"


sections = {"zh": [], "en": []}
found = False
try:
    with open(path, encoding="utf-8") as file:
        changelog = file.read()
except FileNotFoundError:
    changelog = ""

current = None
in_entry = False
for line in changelog.splitlines():
    heading = re.match(r"^## (\S+) - \d{4}-\d{2}-\d{2}\s*$", line)
    if heading or line.startswith("## "):
        if in_entry:
            break
        in_entry = bool(heading) and heading.group(1) == version
        found = found or in_entry
        current = None
        continue
    if not in_entry:
        continue
    if line.strip() == "### 中文":
        current = "zh"
    elif line.strip() == "### English":
        current = "en"
    elif current:
        sections[current].append(line)

zh = "\n".join(sections["zh"]).strip()
en = "\n".join(sections["en"]).strip()
if found and (zh or en):
    zh, en = zh or en, en or zh
else:
    found = False
    print(f"::warning::CHANGELOG.md has no entry for {version}; using generic release notes.")
    zh, en = "- 问题修复与体验改进", "- Bug fixes and improvements"

write("zh.md", zh)
write("en.md", en)
for lang, text in (("zh", zh), ("en", en)):
    write(f"{lang}.txt", clip(plain(text), 4000))
    write(f"{lang}_short.txt", clip(plain(text), 500))
write("found", "true" if found else "false")

print(f"Release notes for {version}:")
print(plain(zh))
print()
print(plain(en))
PY
