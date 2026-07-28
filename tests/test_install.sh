#!/usr/bin/env bash
# Full lifecycle coverage for skills.sh: install, update, enable, disable,
# uninstall, idempotency, source selection and fallback, Codex atomic replace
# and rollback, and isolation from other plugins/skills.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/mocks.sh
. "$REPO_ROOT/tests/lib/mocks.sh"

SKILLS="$REPO_ROOT/skills.sh"
INSTALL_SH="$REPO_ROOT/install.sh"

fresh() {  # start each scenario from a clean sandbox
  teardown_sandbox
  setup_sandbox
  install_mock_claude
  install_mock_codex
}

claude_flag()  { printf '%s\n' "$HOME/.claude/.i-have-work-always"; }
codex_skill()  { printf '%s\n' "$CODEX_HOME/skills/i-have-work"; }
codex_agents() { printf '%s\n' "$CODEX_HOME/AGENTS.md"; }
plugin_listed() { grep -q "^i-have-work@skills|" "$MOCK_STATE/plugins" 2>/dev/null; }

setup_sandbox
trap teardown_sandbox EXIT

echo "== install: both platforms detected =="
fresh
check "install --all --no-permanent" 0 bash "$SKILLS" install --all --no-permanent
check_true "claude plugin registered"       plugin_listed
check_true "codex skill installed"          test -f "$(codex_skill)/SKILL.md"
check_true "codex agents/openai.yaml copied" test -f "$(codex_skill)/agents/openai.yaml"
check_true "opt-in preserved in deployed copy" \
  grep -q "allow_implicit_invocation: false" "$(codex_skill)/agents/openai.yaml"
check_false "permanent NOT enabled by default (claude)" test -f "$(claude_flag)"
check_false "permanent NOT enabled by default (codex)"  test -f "$(codex_agents)"

echo
echo "== install: idempotent =="
check "second install succeeds" 0 bash "$SKILLS" install --all --no-permanent
check_true "codex skill still valid" test -f "$(codex_skill)/SKILL.md"
count="$(grep -c "^i-have-work@skills|" "$MOCK_STATE/plugins" 2>/dev/null || echo 0)"
TESTS_RUN=$((TESTS_RUN+1))
if [ "$count" -eq 1 ]; then echo "OK   plugin not duplicated"
else echo "FAIL plugin duplicated ($count entries)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

echo
echo "== install.sh wrapper =="
fresh
check "install.sh delegates to skills.sh" 0 bash "$INSTALL_SH" --all --no-permanent
check_true "wrapper installed codex skill" test -f "$(codex_skill)/SKILL.md"
check_true "wrapper installed claude plugin" plugin_listed

echo
echo "== install: single platform =="
fresh
check "install --claude only" 0 bash "$SKILLS" install --claude --no-permanent
check_true "claude installed"      plugin_listed
check_false "codex NOT installed"  test -d "$(codex_skill)"

fresh
check "install --codex only" 0 bash "$SKILLS" install --codex --no-permanent
check_true "codex installed"        test -f "$(codex_skill)/SKILL.md"
check_false "claude NOT installed"  plugin_listed

echo
echo "== install: auto-detect single available CLI =="
fresh; remove_mock_codex
check "auto-detect installs claude only" 0 bash "$SKILLS" install --no-permanent
check_true "claude installed"     plugin_listed
check_false "codex not installed" test -d "$(codex_skill)"

fresh; remove_mock_claude
check "auto-detect installs codex only" 0 bash "$SKILLS" install --no-permanent
check_true "codex installed"       test -f "$(codex_skill)/SKILL.md"
check_false "claude not installed" plugin_listed

echo
echo "== install --permanent =="
fresh
check "install --all --permanent" 0 bash "$SKILLS" install --all --permanent
check_true "claude permanent flag created" test -f "$(claude_flag)"
check_true "codex AGENTS.md block created" \
  grep -q "i-have-work:always-on:begin" "$(codex_agents)"

echo
echo "== non-interactive default is off =="
fresh
check "install with no permanent flag, stdin not a TTY" 0 \
  bash -c "bash '$SKILLS' install --all </dev/null"
check_false "did not enable permanent mode" test -f "$(claude_flag)"

echo
echo "== interactive prompt (real PTY) =="
# A pipe is not a TTY, so piping input would only re-test the non-interactive
# path. `script` allocates a real pty, which is what actually exercises the
# prompt. Skip cleanly if util-linux script is unavailable.
if command -v script >/dev/null 2>&1; then
  # Feed the answer into `script`, not into the inner bash: script forwards its
  # own stdin to the child's pty, so the child sees a real TTY *and* the input.
  # Piping directly into bash would leave stdin a pipe and silently re-test the
  # non-interactive path instead.
  fresh
  printf 'y\n' | script -qec "bash '$SKILLS' install --all" /dev/null >/dev/null 2>&1 || true
  check_true "answering 'y' turns permanent on" test -f "$(claude_flag)"
  check_true "'y' also enabled codex permanent mode" \
    grep -q "always-on:begin" "$(codex_agents)"

  fresh
  printf 'n\n' | script -qec "bash '$SKILLS' install --all" /dev/null >/dev/null 2>&1 || true
  check_false "answering 'n' leaves permanent off" test -f "$(claude_flag)"
  check_true "'n' still installs the skill" test -f "$(codex_skill)/SKILL.md"

  fresh
  printf '\n' | script -qec "bash '$SKILLS' install --all" /dev/null >/dev/null 2>&1 || true
  check_false "empty answer defaults to No" test -f "$(claude_flag)"
  check_true "empty answer still installs the skill" test -f "$(codex_skill)/SKILL.md"

  fresh
  printf 'y\n' | script -qec "bash '$SKILLS' install --all --no-permanent" /dev/null >/dev/null 2>&1 || true
  check_false "--no-permanent suppresses the prompt entirely" test -f "$(claude_flag)"

  fresh
  printf 'y\n' | script -qec "bash '$SKILLS' install --all --permanent" /dev/null >/dev/null 2>&1 || true
  check_true "--permanent needs no prompt" test -f "$(claude_flag)"
else
  echo "SKIP interactive prompt tests (util-linux 'script' not available)"
fi

echo
echo "== non-interactive never blocks =="
fresh
# No stdin at all: must not hang waiting for input.
check "install with closed stdin completes" 0 \
  bash -c "bash '$SKILLS' install --all <&-  >/dev/null 2>&1"
check_false "closed stdin left permanent off" test -f "$(claude_flag)"

echo
echo "== enable / disable idempotency =="
fresh
bash "$SKILLS" install --all --no-permanent >/dev/null 2>&1
check "enable"            0 bash "$SKILLS" enable --all
check_true "claude flag present"  test -f "$(claude_flag)"
check_true "codex block present"  grep -q "always-on:begin" "$(codex_agents)"
check "enable again (idempotent)" 0 bash "$SKILLS" enable --all
blocks="$(grep -c "i-have-work:always-on:begin" "$(codex_agents)" 2>/dev/null || echo 0)"
TESTS_RUN=$((TESTS_RUN+1))
if [ "$blocks" -eq 1 ]; then echo "OK   AGENTS.md block not stacked"
else echo "FAIL AGENTS.md block stacked ($blocks)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi
check "disable"            0 bash "$SKILLS" disable --all
check_false "claude flag gone" test -f "$(claude_flag)"
check_false "codex block gone" grep -q "always-on:begin" "$(codex_agents)"
check "disable again (idempotent)" 0 bash "$SKILLS" disable --all
check_true "skill still installed after disable" test -f "$(codex_skill)/SKILL.md"
check_true "plugin still installed after disable" plugin_listed

echo
echo "== enable preserves existing AGENTS.md content =="
fresh
mkdir -p "$CODEX_HOME"
printf '# my rules\n\nnever deploy on friday\n' > "$(codex_agents)"
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
bash "$SKILLS" enable --codex >/dev/null 2>&1
check_true "user content preserved" grep -q "never deploy on friday" "$(codex_agents)"
bash "$SKILLS" disable --codex >/dev/null 2>&1
check_true "user content survives disable" grep -q "never deploy on friday" "$(codex_agents)"
check_false "managed block removed" grep -q "always-on:begin" "$(codex_agents)"

echo
echo "== update =="
fresh
check "update before install fails" 1 bash "$SKILLS" update --all
bash "$SKILLS" install --all --no-permanent >/dev/null 2>&1
check "update after install succeeds" 0 bash "$SKILLS" update --all
check_true "codex skill still present" test -f "$(codex_skill)/SKILL.md"
check "update --codex only" 0 bash "$SKILLS" update --codex
check "update --claude only" 0 bash "$SKILLS" update --claude

echo
echo "== update preserves permanent mode =="
fresh
bash "$SKILLS" install --all --permanent >/dev/null 2>&1
bash "$SKILLS" update --all >/dev/null 2>&1
check_true "claude permanent still on" test -f "$(claude_flag)"
check_true "codex permanent still on"  grep -q "always-on:begin" "$(codex_agents)"
blocks="$(grep -c "i-have-work:always-on:begin" "$(codex_agents)" 2>/dev/null || echo 0)"
TESTS_RUN=$((TESTS_RUN+1))
if [ "$blocks" -eq 1 ]; then echo "OK   update did not stack AGENTS.md block"
else echo "FAIL update stacked AGENTS.md block ($blocks)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

echo
echo "== uninstall =="
fresh
bash "$SKILLS" install --all --permanent >/dev/null 2>&1
check "uninstall --all" 0 bash "$SKILLS" uninstall --all
check_false "codex skill removed" test -d "$(codex_skill)"
check_false "claude plugin removed" plugin_listed
check_false "claude permanent flag cleared" test -f "$(claude_flag)"
check_false "codex permanent block cleared" grep -q "always-on:begin" "$(codex_agents)"
check_true "codex skills dir itself kept" test -d "$CODEX_HOME/skills"
# Explicit platforms: a repeat uninstall is a safe no-op, not an error.
check "repeat uninstall --all is a safe no-op" 0 bash "$SKILLS" uninstall --all
# Auto-detect with nothing installed: must refuse rather than pretend.
check "bare uninstall with nothing installed fails" 1 bash "$SKILLS" uninstall
check "bare update with nothing installed fails"    1 bash "$SKILLS" update

echo
echo "== uninstall leaves other skills and plugins alone =="
fresh
bash "$SKILLS" install --all --no-permanent >/dev/null 2>&1
mkdir -p "$CODEX_HOME/skills/some-other-skill"
echo "keep me" > "$CODEX_HOME/skills/some-other-skill/SKILL.md"
echo "other-plugin@skills|1.0.0|true" >> "$MOCK_STATE/plugins"
bash "$SKILLS" uninstall --all >/dev/null 2>&1
check_true "other codex skill untouched" test -f "$CODEX_HOME/skills/some-other-skill/SKILL.md"
check_true "other claude plugin untouched" grep -q "^other-plugin@skills|" "$MOCK_STATE/plugins"

echo
echo "== --remove-marketplace safety =="
fresh
bash "$SKILLS" install --claude --no-permanent >/dev/null 2>&1
echo "other-plugin@skills|1.0.0|true" >> "$MOCK_STATE/plugins"
check "refuses while another plugin uses the marketplace" 1 \
  bash "$SKILLS" uninstall --claude --remove-marketplace
check_true "marketplace kept" grep -qx "skills" "$MOCK_STATE/marketplaces"

fresh
bash "$SKILLS" install --claude --no-permanent >/dev/null 2>&1
check "removes marketplace when unused" 0 \
  bash "$SKILLS" uninstall --claude --remove-marketplace
check_false "marketplace gone" grep -qx "skills" "$MOCK_STATE/marketplaces"

echo
echo "== --source selection and fallback =="
fresh
MOCK_GITEA_OK=1 MOCK_GITHUB_OK=1 bash "$SKILLS" install --claude --no-permanent --source gitea >/dev/null 2>&1
check_true "forced gitea used gitea" grep -q "git.skea.io" "$MOCK_STATE/marketplace-source"

fresh
MOCK_GITEA_OK=1 MOCK_GITHUB_OK=1 bash "$SKILLS" install --claude --no-permanent --source github >/dev/null 2>&1
check_true "forced github used github" grep -q "github.com" "$MOCK_STATE/marketplace-source"

fresh
check "forced gitea fails hard when unreachable (no fallback)" 1 \
  env MOCK_GITEA_OK=0 MOCK_GITHUB_OK=1 bash "$SKILLS" install --claude --no-permanent --source gitea
check_false "no marketplace configured after forced failure" \
  grep -qx "skills" "$MOCK_STATE/marketplaces"

fresh
check "forced github fails hard when unreachable" 1 \
  env MOCK_GITEA_OK=1 MOCK_GITHUB_OK=0 bash "$SKILLS" install --claude --no-permanent --source github
fresh
check "auto falls back when first source is down" 0 \
  env MOCK_GITEA_OK=0 MOCK_GITHUB_OK=1 bash "$SKILLS" install --claude --no-permanent --source auto
check_true "auto fell back to github" grep -q "github.com" "$MOCK_STATE/marketplace-source"

fresh
check "auto fails when both sources are down" 1 \
  env MOCK_GITEA_OK=0 MOCK_GITHUB_OK=0 bash "$SKILLS" install --claude --no-permanent --source auto

echo
echo "== Codex atomic replace and rollback =="
fresh
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
echo "SENTINEL-OLD" >> "$(codex_skill)/SKILL.md"
# Make the staging copy fail validation by pointing the source at a broken tree.
brokenrepo="$SANDBOX/broken"
mkdir -p "$brokenrepo"
cp -R "$REPO_ROOT/." "$brokenrepo/" 2>/dev/null || true
rm -f "$brokenrepo/plugins/i-have-work/skills/i-have-work/agents/openai.yaml"
check "update fails when payload is invalid" 1 \
  bash "$brokenrepo/skills.sh" update --codex
check_true "previous install left intact after failed update" \
  grep -q "SENTINEL-OLD" "$(codex_skill)/SKILL.md"
leftovers="$(find "$CODEX_HOME/skills" -maxdepth 1 \
  \( -name '.i-have-work.tmp.*' -o -name '.i-have-work.backup.*' \) 2>/dev/null | wc -l)"
TESTS_RUN=$((TESTS_RUN+1))
if [ "$leftovers" -eq 0 ]; then echo "OK   no staging/backup residue after failure"
else echo "FAIL staging/backup residue left behind ($leftovers)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

echo
echo "== no residue after successful operations =="
fresh
bash "$SKILLS" install --all --no-permanent >/dev/null 2>&1
bash "$SKILLS" update --all >/dev/null 2>&1
leftovers="$(find "$CODEX_HOME/skills" -maxdepth 1 \
  \( -name '.i-have-work.tmp.*' -o -name '.i-have-work.backup.*' \) 2>/dev/null | wc -l)"
TESTS_RUN=$((TESTS_RUN+1))
if [ "$leftovers" -eq 0 ]; then echo "OK   no staging/backup residue after success"
else echo "FAIL staging/backup residue ($leftovers)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

echo
echo "== existing CODEX_HOME is respected, not clobbered =="
fresh
mkdir -p "$CODEX_HOME/skills/pre-existing"
echo "x" > "$CODEX_HOME/skills/pre-existing/SKILL.md"
echo "authdata" > "$CODEX_HOME/auth.json"
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
check_true "pre-existing skill untouched" test -f "$CODEX_HOME/skills/pre-existing/SKILL.md"
check_true "auth.json untouched" grep -q "authdata" "$CODEX_HOME/auth.json"

echo
echo "== paths containing spaces =="
teardown_sandbox
setup_sandbox_with_spaces
install_mock_claude; install_mock_codex
check "install into a path with spaces" 0 bash "$SKILLS" install --all --no-permanent
check_true "skill present in spaced path" test -f "$CODEX_HOME/skills/i-have-work/SKILL.md"
check "enable in spaced path"  0 bash "$SKILLS" enable --all
check_true "permanent flag in spaced path" test -f "$HOME/.claude/.i-have-work-always"
check "disable in spaced path" 0 bash "$SKILLS" disable --all
check "update in spaced path"  0 bash "$SKILLS" update --all
check "status in spaced path"  0 bash "$SKILLS" status --all
check "uninstall in spaced path" 0 bash "$SKILLS" uninstall --all
teardown_sandbox_with_spaces

report
