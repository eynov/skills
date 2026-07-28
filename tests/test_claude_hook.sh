#!/usr/bin/env bash
# Exercises the Claude Code always-on SessionStart hook directly, in an
# isolated CLAUDE_CONFIG_DIR, covering: off by default, on when the flag file
# exists, off again after the flag is removed.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/plugins/i-have-work/hooks/always-on.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export CLAUDE_CONFIG_DIR="$scratch"
fail=0

out="$("$hook")"
if [ -n "$out" ]; then
  echo "FAIL expected no output when flag file is absent, got: $out"
  fail=1
else
  echo "OK   silent when flag file absent"
fi

touch "$scratch/.i-have-work-always"
out="$("$hook")"
if echo "$out" | grep -q "I-HAVE-WORK MODE ACTIVE"; then
  echo "OK   emits ruleset when flag file present"
else
  echo "FAIL expected ruleset output when flag file present"
  fail=1
fi

rm "$scratch/.i-have-work-always"
out="$("$hook")"
if [ -n "$out" ]; then
  echo "FAIL expected silence again after flag file removed"
  fail=1
else
  echo "OK   silent again after flag file removed"
fi

exit "$fail"
