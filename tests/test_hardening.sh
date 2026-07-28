#!/usr/bin/env bash
# Post-review hardening coverage:
#   - capability detection adapts to CLI subcommand renames
#   - a genuinely unusable CLI is reported as "CLI interface changed", not a crash
#   - unparseable/absent versions degrade to "unknown", never to a failure
#   - status reports repository vs installed revision and sync state
#   - self-test behaves correctly, including on an incomplete checkout
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/mocks.sh
. "$REPO_ROOT/tests/lib/mocks.sh"

SKILLS="$REPO_ROOT/skills.sh"

fresh() {
  teardown_sandbox
  setup_sandbox
  install_mock_claude
  install_mock_codex
}

codex_skill() { printf '%s\n' "$CODEX_HOME/skills/i-have-work"; }
codex_prov()  { printf '%s\n' "$CODEX_HOME/.i-have-work-install.json"; }

setup_sandbox
trap teardown_sandbox EXIT

echo "== capability detection: CLI renames its subcommand groups =="
fresh
# The mock advertises "plugins"/"marketplaces" instead of "plugin"/"marketplace".
check "install adapts when the plugin group is renamed" 0 \
  env MOCK_PLUGIN_GROUP=plugins MOCK_MARKETPLACE_GROUP=marketplaces \
      bash "$SKILLS" install --claude --no-permanent
check_true "plugin actually installed via the renamed group" \
  grep -q "^i-have-work@skills|" "$MOCK_STATE/plugins"

fresh
check "status works against a renamed CLI" 0 \
  env MOCK_PLUGIN_GROUP=plugins MOCK_MARKETPLACE_GROUP=marketplaces \
      bash "$SKILLS" status --claude

echo
echo "== capability detection: unusable CLI is reported, not crashed on =="
fresh
# Plugin group missing entirely from help output.
check "install fails cleanly when the plugin group is gone" 1 \
  env MOCK_HIDE_PLUGIN_GROUP=1 MOCK_PLUGIN_GROUP=__none__ \
      bash "$SKILLS" install --claude --no-permanent
check_true "reports 'CLI interface changed' rather than a raw error" \
  bash -c "MOCK_HIDE_PLUGIN_GROUP=1 MOCK_PLUGIN_GROUP=__none__ \
           bash '$SKILLS' install --claude --no-permanent 2>&1 | grep -qi 'interface changed'"

fresh
check_true "doctor reports the interface change instead of crashing" \
  bash -c "MOCK_HIDE_PLUGIN_GROUP=1 MOCK_PLUGIN_GROUP=__none__ \
           bash '$SKILLS' doctor --claude 2>&1 | grep -qi 'interface changed'"

fresh
# Marketplace subgroup missing: install needs it, so this must be reported too.
check "install fails cleanly when the marketplace group is gone" 1 \
  env MOCK_HIDE_MARKETPLACE=1 MOCK_MARKETPLACE_GROUP=__none__ \
      bash "$SKILLS" install --claude --no-permanent

fresh
# Required plugin subcommand missing from the advertised list.
check "install fails cleanly when 'install' is unsupported" 1 \
  env MOCK_PLUGIN_SUBS="list uninstall" bash "$SKILLS" install --claude --no-permanent
check_true "names the missing capability" \
  bash -c "MOCK_PLUGIN_SUBS='list uninstall' bash '$SKILLS' install --claude --no-permanent 2>&1 \
           | grep -q 'install'"

fresh
check "status does not crash when capabilities are missing" 0 \
  env MOCK_PLUGIN_SUBS="list" bash "$SKILLS" status --claude

echo
echo "== version handling: unknown is not a failure =="
fresh
check "doctor passes when --version fails outright" 0 \
  env MOCK_VERSION_FAILS=1 bash "$SKILLS" doctor --claude
check_true "version reported as unknown" \
  bash -c "MOCK_VERSION_FAILS=1 bash '$SKILLS' status --claude 2>&1 | grep -q 'unknown'"

fresh
check "doctor passes with an unrecognisable version string" 0 \
  env MOCK_CLAUDE_VERSION="banana-edition" bash "$SKILLS" doctor --claude
check_true "odd version string is surfaced, not rejected" \
  bash -c "MOCK_CLAUDE_VERSION='banana-edition' bash '$SKILLS' status --claude 2>&1 | grep -q 'banana-edition'"

fresh
remove_mock_claude
check "doctor treats a missing CLI as a warning, not a failure" 0 \
  bash "$SKILLS" doctor --claude

echo
echo "== status: repository vs installed revision =="
fresh
check_true "repository section shows a commit line" \
  bash -c "bash '$SKILLS' status 2>&1 | grep -q 'Commit:'"

fresh
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
check_true "provenance recorded outside the deployed skill directory" test -f "$(codex_prov)"
check_false "deployed payload not polluted with provenance" \
  test -f "$(codex_skill)/.i-have-work-install.json"
check_true "fresh install reports Up to date" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'Up to date'"
check_true "fresh install reports this repo as the source" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'this repo'"

echo "# drift" >> "$(codex_skill)/SKILL.md"
check_true "drifted install reports Update available" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'Update available'"
check "update repairs the drift" 0 bash "$SKILLS" update --codex
check_true "back to Up to date after update" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'Up to date'"

echo
echo "== status: external install detection =="
fresh
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
rm -f "$(codex_prov)"
check_true "no provenance -> External install" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'External install'"

printf '{"repo_root":"/elsewhere/skills","repo_commit":"abcdef1234567890"}\n' > "$(codex_prov)"
check_true "provenance from another checkout -> External install" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'External install'"
check_true "shows the other checkout path" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q '/elsewhere/skills'"
check_true "shows a short revision, not a mangled one" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'Installed rev:   abcdef1$'"

printf '{"repo_root":"/elsewhere/skills"}\n' > "$(codex_prov)"
check_true "external without a recorded commit -> unknown rev" \
  bash -c "bash '$SKILLS' status --codex 2>&1 | grep -q 'Installed rev:   unknown'"

echo
echo "== status: uninstall clears provenance =="
fresh
bash "$SKILLS" install --codex --no-permanent >/dev/null 2>&1
bash "$SKILLS" uninstall --codex >/dev/null 2>&1
check_false "provenance removed on uninstall" test -f "$(codex_prov)"

echo
echo "== status stays read-only with the new reporting =="
fresh
bash "$SKILLS" install --all --no-permanent >/dev/null 2>&1
before="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
bash "$SKILLS" status --all >/dev/null 2>&1
after="$(find "$HOME" -type f 2>/dev/null | sort | md5sum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$before" = "$after" ]; then
  echo "OK   status with version reporting did not modify anything"
else
  echo "FAIL status modified the filesystem"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo
echo "== self-test =="
fresh
# Point a stub repo at a trivial passing/failing runner so we exercise
# self-test without recursively running the whole suite.
stub="$SANDBOX/stub-repo"
mkdir -p "$stub/tests"
cp "$SKILLS" "$stub/skills.sh"
printf '#!/usr/bin/env bash\necho "stub suite ok"\nexit 0\n' > "$stub/tests/run_all.sh"
chmod +x "$stub/tests/run_all.sh"
check "self-test succeeds when the suite passes" 0 bash "$stub/skills.sh" self-test
check_true "prints the running banner" \
  bash -c "bash '$stub/skills.sh' self-test 2>&1 | grep -q 'Running self test'"
check_true "prints PASS" \
  bash -c "bash '$stub/skills.sh' self-test 2>&1 | grep -q 'PASS'"

printf '#!/usr/bin/env bash\necho "stub suite failed"\nexit 1\n' > "$stub/tests/run_all.sh"
check "self-test fails when the suite fails" 1 bash "$stub/skills.sh" self-test
check_true "prints FAIL" \
  bash -c "bash '$stub/skills.sh' self-test 2>&1 | grep -q 'FAIL'"

# Incomplete checkout: must explain, not emit "command not found".
broken="$SANDBOX/broken-repo"
mkdir -p "$broken"
cp "$SKILLS" "$broken/skills.sh"
check "self-test fails on an incomplete checkout" 1 bash "$broken/skills.sh" self-test
check_true "says 'Repository incomplete'" \
  bash -c "bash '$broken/skills.sh' self-test 2>&1 | grep -q 'Repository incomplete'"
check_false "does not emit 'command not found'" \
  bash -c "bash '$broken/skills.sh' self-test 2>&1 | grep -q 'command not found'"

check "self-test rejects a platform option" 2 bash "$SKILLS" self-test --claude
check_true "help lists self-test" \
  bash -c "bash '$SKILLS' help | grep -q 'self-test'"

report
