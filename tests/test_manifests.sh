#!/usr/bin/env bash
# Validates every plugin/marketplace JSON manifest in this repo: well-formed
# JSON (jq), and — when the `claude` CLI is available — passes Claude Code's
# own manifest validator.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

echo "== jq: JSON well-formedness =="
while IFS= read -r -d '' f; do
  if jq empty "$f" >/dev/null 2>&1; then
    echo "OK   $f"
  else
    echo "FAIL $f"
    fail=1
  fi
done < <(find "$repo_root" -name "*.json" -not -path "*/.git/*" -print0)

if command -v claude >/dev/null 2>&1; then
  echo
  echo "== claude plugin validate =="
  if claude plugin validate "$repo_root/plugins/i-have-work" >/dev/null 2>&1; then
    echo "OK   plugins/i-have-work"
  else
    echo "FAIL plugins/i-have-work"
    fail=1
  fi
  if claude plugin validate "$repo_root" >/dev/null 2>&1; then
    echo "OK   repo-root marketplace"
  else
    echo "FAIL repo-root marketplace"
    fail=1
  fi
else
  echo
  echo "SKIP claude plugin validate (claude CLI not on PATH)"
fi

exit "$fail"
