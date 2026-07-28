#!/usr/bin/env bash
# Shared helpers for building a fully isolated test environment.
#
# Every test that sources this file gets its own throwaway HOME, CODEX_HOME and
# PATH containing only mock CLIs. Nothing here ever touches the real
# ~/.claude or ~/.codex.

# PATH as it was before any sandbox existed. setup_sandbox restores this first,
# so tearing down a sandbox can never leave a later setup without coreutils.
# Without this, a second setup_sandbox runs with a PATH pointing into a deleted
# directory, mktemp fails, SANDBOX becomes empty, and paths like "$SANDBOX/bin"
# collapse to "/bin" — which would write mock binaries into system directories.
: "${MOCKS_ORIGINAL_PATH:=$PATH}"
export MOCKS_ORIGINAL_PATH

# Create an isolated sandbox and export the environment pointing at it.
# Usage: setup_sandbox   -> sets SANDBOX, HOME, CODEX_HOME, MOCKBIN, PATH
setup_sandbox() {
  # Always start from a known-good PATH, never the previous sandbox's.
  PATH="$MOCKS_ORIGINAL_PATH"
  export PATH

  SANDBOX="$(mktemp -d)" || {
    echo "setup_sandbox: mktemp failed; refusing to continue" >&2
    exit 1
  }
  # Hard guard: an empty or root-ish SANDBOX would make MOCKBIN resolve to a
  # system directory. Never proceed in that state.
  case "$SANDBOX" in
    ""|"/"|"/bin"|"/usr"|"/usr/bin")
      echo "setup_sandbox: refusing unsafe sandbox path '$SANDBOX'" >&2
      exit 1 ;;
  esac
  [ -d "$SANDBOX" ] || { echo "setup_sandbox: sandbox dir missing" >&2; exit 1; }
  export SANDBOX
  export HOME="$SANDBOX/home"
  export CODEX_HOME="$SANDBOX/home/.codex"
  export CLAUDE_CONFIG_DIR="$SANDBOX/home/.claude"
  MOCKBIN="$SANDBOX/bin"
  export MOCKBIN
  mkdir -p "$HOME" "$MOCKBIN"
  # Build a curated tool directory instead of inheriting /usr/bin, so a real
  # `claude` or `codex` installed on this machine can never leak into a test
  # that is meant to simulate "CLI not present".
  _link_sandbox_tools "$SANDBOX/tools"
  export TOOLSBIN="$SANDBOX/tools"
  export PATH="$MOCKBIN:$SANDBOX/tools"
  # State files the mocks read/write, so tests can assert on them.
  export MOCK_STATE="$SANDBOX/mock-state"
  mkdir -p "$MOCK_STATE"
}

teardown_sandbox() {
  # Restore a known-good PATH first so rm and friends are still resolvable
  # after the sandbox tools directory disappears.
  PATH="$MOCKS_ORIGINAL_PATH"; export PATH
  if [ -n "${SANDBOX:-}" ] && [ -d "${SANDBOX:-}" ]; then
    case "$SANDBOX" in
      ""|"/"|"/bin"|"/usr"|"/usr/bin") : ;;
      *) rm -rf "$SANDBOX" ;;
    esac
  fi
  return 0
}

# Same as setup_sandbox, but the sandbox root contains a space so tests can
# prove every path is quoted correctly.
setup_sandbox_with_spaces() {
  PATH="$MOCKS_ORIGINAL_PATH"; export PATH
  local base
  base="$(mktemp -d)" || { echo "setup_sandbox_with_spaces: mktemp failed" >&2; exit 1; }
  SANDBOX="$base/dir with spaces"
  mkdir -p "$SANDBOX" || exit 1
  export SANDBOX
  export SANDBOX_OUTER="$base"
  export HOME="$SANDBOX/home"
  export CODEX_HOME="$SANDBOX/home/.codex"
  export CLAUDE_CONFIG_DIR="$SANDBOX/home/.claude"
  MOCKBIN="$SANDBOX/bin"; export MOCKBIN
  export MOCK_STATE="$SANDBOX/mock-state"
  mkdir -p "$HOME" "$MOCKBIN" "$MOCK_STATE"
  _link_sandbox_tools "$SANDBOX/tools"
  export PATH="$MOCKBIN:$SANDBOX/tools"
}

teardown_sandbox_with_spaces() {
  PATH="$MOCKS_ORIGINAL_PATH"; export PATH
  [ -n "${SANDBOX_OUTER:-}" ] && [ -d "${SANDBOX_OUTER:-}" ] && rm -rf "$SANDBOX_OUTER"
  return 0
}

# Symlink the coreutils a test needs into a private directory, so the sandbox
# PATH never has to include /usr/bin (where a real claude/codex may live).
_link_sandbox_tools() {
  local toolsbin="$1" tool src
  mkdir -p "$toolsbin"
  for tool in bash sh env cat cp rm mv mkdir rmdir chmod find grep egrep sed awk \
              jq md5sum sha256sum mktemp dirname basename readlink head tail \
              sort cut tr wc ls stat touch xargs date cmp diff git timeout \
              python3 uname id printf test true false script; do
    if src="$(PATH="$MOCKS_ORIGINAL_PATH" command -v "$tool" 2>/dev/null)"; then
      ln -sf "$src" "$toolsbin/$tool" 2>/dev/null || true
    fi
  done
}

# Install a mock `claude` CLI that emulates the real plugin subcommands well
# enough to drive skills.sh: marketplace add/list/remove, plugin
# install/update/uninstall/enable/disable/list --json.
# Refuse to write a mock anywhere outside an active sandbox. This is a
# belt-and-braces guard: MOCKBIN must live under SANDBOX and never be a system
# directory, no matter how the harness is invoked.
assert_safe_mockbin() {
  case "${SANDBOX:-}" in ""|"/") echo "mocks: SANDBOX unset/unsafe" >&2; exit 1 ;; esac
  case "${MOCKBIN:-}" in
    ""|"/bin"|"/usr/bin"|"/usr/local/bin"|"/sbin"|"/usr/sbin")
      echo "mocks: refusing to write mocks into system dir '${MOCKBIN:-}'" >&2; exit 1 ;;
  esac
  case "$MOCKBIN" in
    "$SANDBOX"/*) : ;;
    *) echo "mocks: MOCKBIN '$MOCKBIN' is outside SANDBOX '$SANDBOX'" >&2; exit 1 ;;
  esac
  [ -d "$MOCKBIN" ] || mkdir -p "$MOCKBIN"
}

install_mock_claude() {
  assert_safe_mockbin
  cat >"$MOCKBIN/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
state="${MOCK_STATE:?}"
mp="$state/marketplaces"      # one line per marketplace name
pl="$state/plugins"           # lines: id|version|enabled
touch "$mp" "$pl"

# Simulated remote reachability, controlled by the test.
src_ok() {
  case "$1" in
    *git.skea.io*) [ "${MOCK_GITEA_OK:-1}" = "1" ] ;;
    *github.com*)  [ "${MOCK_GITHUB_OK:-1}" = "1" ] ;;
    *)             return 0 ;;
  esac
}

# The group name this mock responds to; tests override to simulate a rename.
GROUP="${MOCK_PLUGIN_GROUP:-plugin}"
MPGROUP="${MOCK_MARKETPLACE_GROUP:-marketplace}"

# Top-level --help must advertise the group token, since capability detection
# looks for the identifier rather than parsing prose or gating on a version.
if [ "${1:-}" = "--help" ] || [ -z "${1:-}" ]; then
  echo "Usage: claude [options] [command]"
  echo "Commands:"
  [ "${MOCK_HIDE_PLUGIN_GROUP:-0}" = "1" ] || echo "  $GROUP    Manage plugins"
  echo "  mcp       Manage MCP servers"
  exit 0
fi

case "${1:-}" in
  --version)
    [ "${MOCK_VERSION_FAILS:-0}" = "1" ] && exit 1
    echo "${MOCK_CLAUDE_VERSION:-1.2.3 (Claude Code Mock)}"; exit 0 ;;
esac

if [ "${1:-}" != "$GROUP" ]; then
  # Unknown group: mimic the real CLI, which falls back to top-level help
  # and still exits 0 — which is exactly why exit codes cannot be trusted.
  echo "Usage: claude [options] [command]"
  echo "Commands:"
  [ "${MOCK_HIDE_PLUGIN_GROUP:-0}" = "1" ] || echo "  $GROUP    Manage plugins"
  exit 0
fi
shift

# Group help: advertise available subcommands as bare tokens.
if [ "${1:-}" = "--help" ] || [ -z "${1:-}" ]; then
  echo "Usage: claude $GROUP [command]"
  echo "Commands:"
  for sub in ${MOCK_PLUGIN_SUBS:-install list uninstall update enable disable}; do
    echo "  $sub"
  done
  [ "${MOCK_HIDE_MARKETPLACE:-0}" = "1" ] || echo "  $MPGROUP"
  exit 0
fi

case "${1:-}" in
  "$MPGROUP")
    shift
    if [ "${1:-}" = "--help" ] || [ -z "${1:-}" ]; then
      echo "Usage: claude $GROUP $MPGROUP [command]"
      echo "Commands:"
      for sub in ${MOCK_MARKETPLACE_SUBS:-add list remove update}; do
        echo "  $sub"
      done
      exit 0
    fi
    case "${1:-}" in
      add)
        shift
        target="${1:-}"
        if ! src_ok "$target"; then
          echo "✘ Failed to add marketplace: could not reach $target" >&2; exit 1
        fi
        if grep -qx "skills" "$mp"; then
          echo "✔ Marketplace 'skills' already on disk"; exit 0
        fi
        echo "skills" >>"$mp"
        echo "$target" >"$state/marketplace-source"
        echo "✔ Successfully added marketplace: skills"; exit 0 ;;
      list)
        if [ "${2:-}" = "--json" ]; then
          if [ -s "$mp" ]; then
            printf '[{"name":"skills","source":"git","path":"%s"}]\n' \
              "$(cat "$state/marketplace-source" 2>/dev/null || echo unknown)"
          else echo "[]"; fi
        else
          if [ -s "$mp" ]; then echo "Configured marketplaces:"; sed 's/^/  /' "$mp"
          else echo "No marketplaces configured"; fi
        fi
        exit 0 ;;
      remove)
        shift; name="${1:-}"
        if grep -qx "$name" "$mp"; then
          grep -vx "$name" "$mp" >"$mp.new" || true; mv "$mp.new" "$mp"
          echo "✔ Successfully removed marketplace: $name"; exit 0
        fi
        echo "✘ Marketplace not found: $name" >&2; exit 1 ;;
      update)
        shift; name="${1:-}"
        grep -qx "$name" "$mp" || { echo "✘ Marketplace not found: $name" >&2; exit 1; }
        echo "✔ Successfully updated marketplace: $name"; exit 0 ;;
      *) echo "mock claude: bad marketplace subcommand" >&2; exit 1 ;;
    esac ;;
  install)
    shift; id="${1:-}"
    grep -qx "skills" "$mp" || { echo "✘ Marketplace not configured" >&2; exit 1; }
    if grep -q "^${id}|" "$pl"; then echo "✔ Plugin \"$id\" is already installed"; exit 0; fi
    echo "${id}|${MOCK_PLUGIN_VERSION:-0.1.0}|true" >>"$pl"
    echo "✔ Successfully installed plugin: $id"; exit 0 ;;
  update)
    shift; id="${1:-}"
    grep -q "^${id}|" "$pl" || { echo "✘ Plugin \"$id\" not found" >&2; exit 1; }
    sed -i "s#^${id}|[^|]*|#${id}|${MOCK_PLUGIN_VERSION:-0.2.0}|#" "$pl"
    echo "✔ Plugin \"$id\" updated"; exit 0 ;;
  uninstall)
    shift; name="${1:-}"
    if grep -q "^${name}@" "$pl" || grep -q "^${name}|" "$pl"; then
      grep -v "^${name}@" "$pl" | grep -v "^${name}|" >"$pl.new" || true
      mv "$pl.new" "$pl"
      echo "✔ Successfully uninstalled plugin: $name"; exit 0
    fi
    echo "✘ Failed to uninstall plugin \"$name\": not found" >&2; exit 1 ;;
  enable|disable)
    action="$1"; shift; name="${1:-}"
    val=true; [ "$action" = "disable" ] && val=false
    if grep -q "^${name}@" "$pl"; then
      sed -i "s#^\(${name}@[^|]*|[^|]*|\).*#\1${val}#" "$pl"
      echo "✔ Successfully ${action}d plugin: $name"; exit 0
    fi
    echo "✘ Plugin not found: $name" >&2; exit 1 ;;
  list)
    if [ "${2:-}" = "--json" ] || [ "${1:-}" = "--json" ]; then
      out="["; first=1
      while IFS='|' read -r id ver en; do
        [ -n "$id" ] || continue
        [ $first -eq 1 ] || out="$out,"
        first=0
        out="$out{\"id\":\"$id\",\"version\":\"$ver\",\"scope\":\"user\",\"enabled\":$en,\"installPath\":\"${MOCK_INSTALL_PATH:-}\"}"
      done <"$pl"
      echo "$out]"
    else
      if [ -s "$pl" ]; then echo "Installed plugins:"; sed 's/^/  /' "$pl"
      else echo "No plugins installed"; fi
    fi
    exit 0 ;;
  *) echo "mock claude: unsupported plugin subcommand: ${1:-}" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$MOCKBIN/claude"
}

install_mock_codex() {
  assert_safe_mockbin
  cat >"$MOCKBIN/codex" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "codex-mock 1.0.0"; exit 0 ;;
  *) echo "codex mock"; exit 0 ;;
esac
MOCK
  chmod +x "$MOCKBIN/codex"
}

remove_mock_claude() { rm -f "$MOCKBIN/claude"; }
remove_mock_codex()  { rm -f "$MOCKBIN/codex"; }

# --- tiny assertion helpers -------------------------------------------------

TESTS_RUN=0
TESTS_FAILED=0

check() {  # check <description> <expected-exit> <command...>
  local desc="$1" expected="$2"; shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "OK   $desc"
  else
    echo "FAIL $desc (expected exit $expected, got $actual)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

check_true() {  # check_true <description> <command...>
  local desc="$1"; shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@" >/dev/null 2>&1; then
    echo "OK   $desc"
  else
    echo "FAIL $desc"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

check_false() {  # check_false <description> <command...>
  local desc="$1"; shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@" >/dev/null 2>&1; then
    echo "FAIL $desc (expected failure, got success)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo "OK   $desc"
  fi
}

report() {
  echo
  if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "passed $TESTS_RUN/$TESTS_RUN"
    return 0
  fi
  echo "FAILED $TESTS_FAILED of $TESTS_RUN"
  return 1
}
