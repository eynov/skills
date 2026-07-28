#!/usr/bin/env sh
# Turns off i-have-work always-on for Codex by removing exactly the managed
# block added by codex-enable-always.sh from $CODEX_HOME/AGENTS.md. Everything
# else in the file — including content the user wrote by hand — is preserved.
set -eu

codex_home="${CODEX_HOME:-$HOME/.codex}"
agents_file="$codex_home/AGENTS.md"
begin_marker="<!-- i-have-work:always-on:begin -->"
end_marker="<!-- i-have-work:always-on:end -->"

if [ ! -f "$agents_file" ]; then
  echo "$agents_file does not exist — nothing to disable."
  exit 0
fi

if ! grep -qF "$begin_marker" "$agents_file"; then
  echo "No i-have-work always-on block found in $agents_file — nothing to disable."
  exit 0
fi

tmp_file=$(mktemp "${TMPDIR:-/tmp}/i-have-work-agents.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT

awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin { skipping = 1; next }
  $0 == end   { skipping = 0; next }
  !skipping   { print }
' "$agents_file" > "$tmp_file"

mv "$tmp_file" "$agents_file"
trap - EXIT

echo "i-have-work always-on disabled: removed the managed block from $agents_file"
