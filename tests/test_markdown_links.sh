#!/usr/bin/env bash
# Verifies that every relative link in the repo's Markdown files points at a
# file that actually exists. Remote (http/https) links are listed but not
# fetched, so this test stays offline and fast.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

broken=0
checked=0
remote=0

while IFS= read -r -d '' md; do
  rel="${md#"$REPO_ROOT"/}"
  dir="$(dirname -- "$md")"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*) remote=$((remote + 1)); continue ;;
      \#*) continue ;;                        # in-page anchor
    esac
    target="${target%%#*}"                    # strip anchor fragment
    [ -n "$target" ] || continue
    checked=$((checked + 1))
    case "$target" in
      /*) resolved="$REPO_ROOT$target" ;;     # repo-absolute
      *)  resolved="$dir/$target" ;;
    esac
    if [ ! -e "$resolved" ]; then
      echo "FAIL $rel -> $target"
      broken=$((broken + 1))
    fi
  done < <(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(find "$REPO_ROOT" -name '*.md' -not -path '*/.git/*' -print0)

echo "OK   checked $checked local links across the repo ($remote remote links skipped)"

if [ "$broken" -gt 0 ]; then
  echo "FAILED $broken broken local link(s)"
  exit 1
fi
echo "OK   all local Markdown links resolve"
exit 0
