#!/usr/bin/env bash
# Exercises the Codex always-on enable/disable scripts in an isolated
# CODEX_HOME, covering: fresh install, idempotent re-run, preservation of
# pre-existing AGENTS.md content, clean removal, and idempotent disable.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
enable_script="$repo_root/plugins/i-have-work/scripts/codex-enable-always.sh"
disable_script="$repo_root/plugins/i-have-work/scripts/codex-disable-always.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export CODEX_HOME="$scratch"
agents_file="$scratch/AGENTS.md"
fail=0

sh "$enable_script" >/dev/null
if grep -q "i-have-work:always-on:begin" "$agents_file" 2>/dev/null; then
  echo "OK   fresh install appends managed block"
else
  echo "FAIL fresh install did not create the managed block"
  fail=1
fi

before_hash="$(md5sum "$agents_file" | awk '{print $1}')"
sh "$enable_script" >/dev/null
after_hash="$(md5sum "$agents_file" | awk '{print $1}')"
if [ "$before_hash" = "$after_hash" ]; then
  echo "OK   re-running enable is idempotent (file unchanged)"
else
  echo "FAIL re-running enable changed the file"
  fail=1
fi

rm -f "$agents_file"
printf '# My existing rules\n\nDo not touch prod on Fridays.\n' > "$agents_file"
sh "$enable_script" >/dev/null
if grep -q "Fridays" "$agents_file" && grep -q "i-have-work:always-on:begin" "$agents_file"; then
  echo "OK   enable preserves pre-existing AGENTS.md content"
else
  echo "FAIL enable did not preserve pre-existing content correctly"
  fail=1
fi

sh "$disable_script" >/dev/null
if grep -q "Fridays" "$agents_file" && ! grep -q "i-have-work:always-on" "$agents_file"; then
  echo "OK   disable removes only the managed block"
else
  echo "FAIL disable did not cleanly remove only the managed block"
  fail=1
fi

# Idempotent disable: must not error when there is nothing to remove.
if sh "$disable_script" >/dev/null; then
  echo "OK   re-running disable on an already-clean file is a safe no-op"
else
  echo "FAIL re-running disable failed"
  fail=1
fi

exit "$fail"
