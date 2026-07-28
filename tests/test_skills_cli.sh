#!/usr/bin/env bash
# Argument handling, help, platform selection, and read-only guarantees for
# skills.sh. Runs entirely inside an isolated sandbox with mock CLIs.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/mocks.sh
. "$REPO_ROOT/tests/lib/mocks.sh"

SKILLS="$REPO_ROOT/skills.sh"
setup_sandbox
trap teardown_sandbox EXIT

echo "== help and usage =="
check "help subcommand"          0 bash "$SKILLS" help
check "--help"                   0 bash "$SKILLS" --help
check "-h"                       0 bash "$SKILLS" -h
check "no arguments prints help" 0 bash "$SKILLS"
check "install --help"           0 bash "$SKILLS" install --help
check_true "help mentions all subcommands" \
  bash -c "bash '$SKILLS' help | grep -q install && \
           bash '$SKILLS' help | grep -q update && \
           bash '$SKILLS' help | grep -q uninstall && \
           bash '$SKILLS' help | grep -q enable && \
           bash '$SKILLS' help | grep -q disable && \
           bash '$SKILLS' help | grep -q status && \
           bash '$SKILLS' help | grep -q doctor"

echo
echo "== invalid input =="
check "unknown command"                2 bash "$SKILLS" not-a-command
check "unknown option"                 2 bash "$SKILLS" install --nope
check "unknown global option"          2 bash "$SKILLS" --nope
check "--permanent + --no-permanent"   2 bash "$SKILLS" install --permanent --no-permanent
check "--no-permanent + --permanent"   2 bash "$SKILLS" install --no-permanent --permanent
check "--claude + --codex"             2 bash "$SKILLS" install --claude --codex
check "--claude + --all"               2 bash "$SKILLS" install --claude --all
check "invalid --source value"         2 bash "$SKILLS" install --source nope
check "invalid --source= value"        2 bash "$SKILLS" install --source=nope
check "--source with no value"         2 bash "$SKILLS" install --source
check "--remove-marketplace on status" 2 bash "$SKILLS" status --remove-marketplace
check "--remove-marketplace on install" 2 bash "$SKILLS" install --remove-marketplace

echo
echo "== no CLI present =="
remove_mock_claude; remove_mock_codex
check "install fails when no CLI found"   1 bash "$SKILLS" install --no-permanent
check "update fails when nothing installed"   1 bash "$SKILLS" update
check "uninstall fails when nothing installed" 1 bash "$SKILLS" uninstall
check "explicit --claude fails without CLI" 1 bash "$SKILLS" install --claude --no-permanent
check "explicit --codex fails without CLI"  1 bash "$SKILLS" install --codex --no-permanent
check "status still works with no CLI"    0 bash "$SKILLS" status
check_true "status reports Claude not installed" \
  bash -c "bash '$SKILLS' status | grep -A2 'Claude Code' | grep -q 'not installed'"
check_true "status reports Codex not installed" \
  bash -c "bash '$SKILLS' status | grep -A2 'Codex' | grep -q 'not installed'"

echo
echo "== status is read-only =="
install_mock_claude; install_mock_codex
before="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
bash "$SKILLS" status >/dev/null 2>&1
bash "$SKILLS" status --all >/dev/null 2>&1
after="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$before" = "$after" ]; then
  echo "OK   status did not modify the filesystem"
else
  echo "FAIL status modified the filesystem"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo
echo "== doctor =="
check_true "doctor runs and reports" bash -c "bash '$SKILLS' doctor >/dev/null 2>&1 || true"
check_true "doctor validates opt-in invariant" \
  bash -c "bash '$SKILLS' doctor 2>&1 | grep -q 'allow_implicit_invocation: false'"
check_true "doctor flags the documented Codex validator conflict" \
  bash -c "bash '$SKILLS' doctor 2>&1 | grep -qi 'disable-model-invocation'"
before="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
bash "$SKILLS" doctor >/dev/null 2>&1 || true
after="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$before" = "$after" ]; then
  echo "OK   doctor did not modify the filesystem"
else
  echo "FAIL doctor modified the filesystem"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo
echo "== runs from any working directory =="
check "absolute path invocation from /" 0 bash -c "cd / && bash '$SKILLS' status"
check "absolute path invocation from /tmp" 0 bash -c "cd /tmp && bash '$SKILLS' help"

report
