#!/usr/bin/env bash
# Runs every check for this repo: shellcheck over all shell scripts, JSON/
# manifest validation, and the i-have-work enable/disable behavioral tests.
# Exits non-zero if anything fails.
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

echo "########## shellcheck ##########"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    first_line="$(head -n1 "$f")"
    case "$first_line" in
      *bash) dialect="bash" ;;
      *) dialect="sh" ;;
    esac
    # -x lets shellcheck follow `source`d helper libraries (tests/lib/mocks.sh)
    # instead of emitting SC1091 and failing the run.
    if shellcheck -x -s "$dialect" "$f"; then
      echo "OK   $f"
    else
      fail=1
    fi
  done < <(find "$repo_root" \( -name "*.sh" \) -not -path "*/.git/*" -print0)
else
  echo "SKIP shellcheck not installed"
fi

echo
echo "########## manifests ##########"
bash "$repo_root/tests/test_manifests.sh" || fail=1

echo
echo "########## opt-in invariant ##########"
bash "$repo_root/tests/test_opt_in_invariant.sh" || fail=1

echo
echo "########## claude always-on hook ##########"
bash "$repo_root/tests/test_claude_hook.sh" || fail=1

echo
echo "########## codex AGENTS.md toggle ##########"
bash "$repo_root/tests/test_codex_agents_toggle.sh" || fail=1

echo
echo "########## markdown links ##########"
bash "$repo_root/tests/test_markdown_links.sh" || fail=1

echo
echo "########## skills.sh CLI ##########"
bash "$repo_root/tests/test_skills_cli.sh" || fail=1

echo
echo "########## skills.sh lifecycle (install/update/enable/disable/uninstall) ##########"
bash "$repo_root/tests/test_install.sh" || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "SOME CHECKS FAILED"
fi
exit "$fail"
