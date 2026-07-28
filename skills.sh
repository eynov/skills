#!/usr/bin/env bash
#
# skills.sh — unified lifecycle manager for the i-have-work Agent Skill.
#
#   install    deploy the skill to Claude Code and/or Codex
#   update     redeploy this repo's version over an existing install
#   uninstall  remove the skill (and turn off permanent mode first)
#   enable     turn on permanent mode (applies to every new session)
#   disable    turn off permanent mode (the skill stays installed)
#   status     read-only report of what is installed and enabled
#   doctor     read-only diagnostics
#   self-test  run this repository's full test suite
#   help       usage
#
# Design notes:
#   - Opt-in by default. Nothing becomes permanent unless asked for.
#   - Idempotent: every command is safe to run twice.
#   - Never touches other plugins, skills, marketplaces, or user config.
#   - Never reads or prints credentials, and never modifies git remotes or
#     fetches from the network on the user's behalf.
#   - `update` redeploys what is in THIS repo. It deliberately does not run
#     git pull, because the repo may be a ZIP export or a read-only mount.
#
# Gitea (git.skea.io/S/skills) is the authoritative source.
# GitHub (github.com/eynov/skills) is a read-only distribution mirror.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Constants and repo location
# ---------------------------------------------------------------------------

SKILL_NAME="i-have-work"
MARKETPLACE_NAME="skills"
PLUGIN_ID="${SKILL_NAME}@${MARKETPLACE_NAME}"

GITEA_URL="https://git.skea.io/S/skills.git"
GITHUB_URL="https://github.com/eynov/skills.git"

# Resolve the repo from this script's own location so the tool works from any
# working directory, including `bash /opt/work/skills/skills.sh install`.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
  link_target="$(readlink "$SCRIPT_PATH")"
  case "$link_target" in
    /*) SCRIPT_PATH="$link_target" ;;
    *)  SCRIPT_PATH="$(dirname -- "$SCRIPT_PATH")/$link_target" ;;
  esac
done
REPO_ROOT="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

SKILL_SRC="$REPO_ROOT/plugins/$SKILL_NAME/skills/$SKILL_NAME"
CODEX_ENABLE_SCRIPT="$REPO_ROOT/plugins/$SKILL_NAME/scripts/codex-enable-always.sh"
CODEX_DISABLE_SCRIPT="$REPO_ROOT/plugins/$SKILL_NAME/scripts/codex-disable-always.sh"

claude_config_dir() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
claude_flag_file()  { printf '%s\n' "$(claude_config_dir)/.${SKILL_NAME}-always"; }
codex_home()        { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }
codex_skill_dir()   { printf '%s\n' "$(codex_home)/skills/$SKILL_NAME"; }

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_DIM=""
fi

info()  { printf '%s\n' "$*"; }
step()  { printf '%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s  warn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s  fail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

die() { err "$*"; exit 1; }

# Track per-platform outcomes so a partial failure still exits non-zero with a
# summary rather than a misleading success.
declare -a RESULT_LINES=()
RESULT_FAILED=0
record_ok()   { RESULT_LINES+=("ok|$1|$2"); }
record_fail() { RESULT_LINES+=("fail|$1|$2"); RESULT_FAILED=1; }

print_summary() {
  [ "${#RESULT_LINES[@]}" -gt 0 ] || return 0
  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  local line status platform detail
  for line in "${RESULT_LINES[@]}"; do
    IFS='|' read -r status platform detail <<<"$line"
    if [ "$status" = "ok" ]; then
      printf '  %s%-7s%s %-12s %s\n' "$C_GREEN" "ok" "$C_RESET" "$platform" "$detail"
    else
      printf '  %s%-7s%s %-12s %s\n' "$C_RED" "FAILED" "$C_RESET" "$platform" "$detail"
    fi
  done
}

# ---------------------------------------------------------------------------
# CLI detection
# ---------------------------------------------------------------------------

find_claude_cli() {
  if command -v claude >/dev/null 2>&1; then command -v claude; return 0; fi
  local c
  for c in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" \
           "/usr/local/bin/claude" "/opt/homebrew/bin/claude"; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Codex may be installed as a standalone binary outside PATH.
find_codex_cli() {
  if command -v codex >/dev/null 2>&1; then command -v codex; return 0; fi
  local c
  for c in "$HOME/.local/bin/codex" "$HOME/.codex/bin/codex" \
           "/usr/local/bin/codex" "/opt/homebrew/bin/codex"; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

have_claude() { find_claude_cli >/dev/null 2>&1; }
have_codex()  { find_codex_cli  >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Capability detection
#
# We drive the Claude CLI through whatever subcommand names it actually
# advertises, rather than hardcoding them or gating on a version number.
#
# Exit codes alone are not usable for this: `claude <unknown-group> --help`
# exits 0 (it falls back to printing top-level help), and
# `claude plugin <unknown-sub> --help` exits 0 as well. So a probe based only on
# exit status reports every subcommand as supported.
#
# Instead we look for the subcommand *identifier* in the relevant `--help`
# output. Command identifiers are stable tokens, not translated prose, so this
# does not depend on any particular English sentence or output layout — only on
# the CLI listing its own subcommand names somewhere in its help.
#
# If the CLI is reorganised (say `plugin` becomes `plugins`), the candidate
# lists below let us adapt automatically. If nothing matches, we report
# "CLI interface changed" rather than failing with a confusing error.
# ---------------------------------------------------------------------------

CAP_PLUGIN_GROUP=""      # e.g. "plugin"
CAP_MARKETPLACE_GROUP="" # e.g. "marketplace"
CAP_PROBED="no"

# Does <token> appear as a word in the help output of the given command?
_help_lists_token() {  # _help_lists_token <token> <cmd> [args...]
  local token="$1"; shift
  "$@" --help 2>&1 | grep -qw -- "$token"
}

# Discover the plugin group name and the marketplace group name. Safe to call
# repeatedly; results are cached for the life of the process.
probe_claude_capabilities() {
  [ "$CAP_PROBED" = "yes" ] && return 0
  CAP_PROBED="yes"

  local cli
  cli="$(find_claude_cli 2>/dev/null)" || return 1

  local candidate
  for candidate in plugin plugins; do
    if _help_lists_token "$candidate" "$cli"; then
      CAP_PLUGIN_GROUP="$candidate"; break
    fi
  done
  [ -n "$CAP_PLUGIN_GROUP" ] || return 1

  for candidate in marketplace marketplaces; do
    if _help_lists_token "$candidate" "$cli" "$CAP_PLUGIN_GROUP"; then
      CAP_MARKETPLACE_GROUP="$candidate"; break
    fi
  done
  return 0
}

# Is <subcommand> available under the plugin group?
claude_supports() {  # claude_supports <subcommand>
  probe_claude_capabilities || return 1
  [ -n "$CAP_PLUGIN_GROUP" ] || return 1
  local cli; cli="$(find_claude_cli 2>/dev/null)" || return 1
  _help_lists_token "$1" "$cli" "$CAP_PLUGIN_GROUP"
}

# Is <subcommand> available under the marketplace group?
claude_marketplace_supports() {  # claude_marketplace_supports <subcommand>
  probe_claude_capabilities || return 1
  [ -n "$CAP_MARKETPLACE_GROUP" ] || return 1
  local cli; cli="$(find_claude_cli 2>/dev/null)" || return 1
  _help_lists_token "$1" "$cli" "$CAP_PLUGIN_GROUP" "$CAP_MARKETPLACE_GROUP"
}

# Run `claude <plugin-group> ...`
claude_plugin_cmd() {
  local cli; cli="$(find_claude_cli 2>/dev/null)" || return 1
  probe_claude_capabilities || return 1
  [ -n "$CAP_PLUGIN_GROUP" ] || return 1
  "$cli" "$CAP_PLUGIN_GROUP" "$@"
}

# Run `claude <plugin-group> <marketplace-group> ...`
claude_marketplace_cmd() {
  local cli; cli="$(find_claude_cli 2>/dev/null)" || return 1
  probe_claude_capabilities || return 1
  [ -n "$CAP_PLUGIN_GROUP" ] && [ -n "$CAP_MARKETPLACE_GROUP" ] || return 1
  "$cli" "$CAP_PLUGIN_GROUP" "$CAP_MARKETPLACE_GROUP" "$@"
}

# The subcommands install/update actually need. Returns the missing ones.
claude_missing_capabilities() {
  local missing=""
  probe_claude_capabilities || { printf 'plugin-group\n'; return 0; }
  if [ -z "$CAP_PLUGIN_GROUP" ]; then printf 'plugin-group\n'; return 0; fi
  local sub
  for sub in install list uninstall; do
    claude_supports "$sub" || missing="$missing $sub"
  done
  if [ -z "$CAP_MARKETPLACE_GROUP" ]; then
    missing="$missing marketplace-group"
  else
    for sub in add list; do
      claude_marketplace_supports "$sub" || missing="$missing marketplace-$sub"
    done
  fi
  printf '%s\n' "${missing# }"
}

# A human-readable version string, or "unknown". Never fails the caller.
claude_version_string() {
  local cli v
  cli="$(find_claude_cli 2>/dev/null)" || { printf 'unknown\n'; return 0; }
  v="$("$cli" --version 2>/dev/null | head -1 | tr -d '\r')" || v=""
  [ -n "$v" ] && printf '%s\n' "$v" || printf 'unknown\n'
}

codex_version_string() {
  local cli v
  cli="$(find_codex_cli 2>/dev/null)" || { printf 'unknown\n'; return 0; }
  v="$("$cli" --version 2>/dev/null | head -1 | tr -d '\r')" || v=""
  [ -n "$v" ] && printf '%s\n' "$v" || printf 'unknown\n'
}

# ---------------------------------------------------------------------------
# Install-state probes (read-only)
# ---------------------------------------------------------------------------

claude_plugin_installed() {
  local json
  json="$(claude_plugin_cmd list --json 2>/dev/null)" || return 1
  printf '%s' "$json" | jq -e --arg id "$PLUGIN_ID" \
    'if type=="array" then any(.[]; .id == $id) else false end' >/dev/null 2>&1
}

claude_plugin_enabled() {
  local json
  json="$(claude_plugin_cmd list --json 2>/dev/null)" || return 1
  printf '%s' "$json" | jq -e --arg id "$PLUGIN_ID" \
    'if type=="array" then any(.[]; .id == $id and .enabled == true) else false end' >/dev/null 2>&1
}

claude_plugin_version() {
  claude_plugin_cmd list --json 2>/dev/null \
    | jq -r --arg id "$PLUGIN_ID" \
      'if type=="array" then (.[] | select(.id==$id) | .version) else empty end' 2>/dev/null \
    | head -1
}

# Where Claude Code unpacked the plugin, if it reports it.
claude_plugin_install_path() {
  claude_plugin_cmd list --json 2>/dev/null \
    | jq -r --arg id "$PLUGIN_ID" \
      'if type=="array" then (.[] | select(.id==$id) | .installPath // empty) else empty end' 2>/dev/null \
    | head -1
}

claude_marketplace_present() {
  claude_marketplace_cmd list --json 2>/dev/null \
    | jq -e --arg n "$MARKETPLACE_NAME" \
      'if type=="array" then any(.[]; .name == $n) else false end' >/dev/null 2>&1
}

# Other plugins installed from our marketplace — guards --remove-marketplace.
claude_other_plugins_in_marketplace() {
  claude_plugin_cmd list --json 2>/dev/null \
    | jq -r --arg mp "@$MARKETPLACE_NAME" --arg id "$PLUGIN_ID" \
      'if type=="array" then (.[] | select(.id != $id) | select(.id | endswith($mp)) | .id) else empty end' 2>/dev/null
}

claude_permanent_on() { [ -f "$(claude_flag_file)" ]; }
codex_skill_installed() { [ -f "$(codex_skill_dir)/SKILL.md" ]; }

# ---------------------------------------------------------------------------
# Provenance and fingerprints
#
# A fingerprint is a content hash of the skill payload, so "is the installed
# copy the same as this repo's copy" is answerable without guessing.
#
# Provenance is a small JSON record written NEXT TO the install (never inside
# the deployed skill directory, so the deployed payload stays byte-identical to
# the repo). It records which checkout deployed it and at which commit, which
# is what lets status distinguish "installed by this repo" from an external or
# manual install.
# ---------------------------------------------------------------------------

CLAUDE_PROVENANCE_FILE() { printf '%s\n' "$(claude_config_dir)/.${SKILL_NAME}-install.json"; }
CODEX_PROVENANCE_FILE()  { printf '%s\n' "$(codex_home)/.${SKILL_NAME}-install.json"; }

# Hash of the skill payload in a directory. Empty output means "cannot tell".
payload_fingerprint() {  # payload_fingerprint <dir>
  local dir="$1"
  [ -f "$dir/SKILL.md" ] || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  {
    cat "$dir/SKILL.md"
    [ -f "$dir/agents/openai.yaml" ] && cat "$dir/agents/openai.yaml"
  } 2>/dev/null | sha256sum | cut -d' ' -f1
}

repo_fingerprint() { payload_fingerprint "$SKILL_SRC"; }

repo_commit_full() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null && return 0
  fi
  return 1
}

write_provenance() {  # write_provenance <file> <source-note>
  local file="$1" source_note="${2:-}" commit fp now
  commit="$(repo_commit_full 2>/dev/null || echo '')"
  fp="$(repo_fingerprint 2>/dev/null || echo '')"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '')"
  mkdir -p -- "$(dirname -- "$file")" 2>/dev/null || return 0
  # Best-effort: provenance is a convenience, never a reason to fail an install.
  cat >"$file" 2>/dev/null <<EOF || return 0
{
  "installed_by": "skills.sh",
  "skill": "$SKILL_NAME",
  "repo_root": "$REPO_ROOT",
  "repo_commit": "$commit",
  "payload_fingerprint": "$fp",
  "source": "$source_note",
  "installed_at": "$now"
}
EOF
  return 0
}

read_provenance_field() {  # read_provenance_field <file> <key>
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
}

remove_provenance() { [ -f "$1" ] && rm -f -- "$1"; return 0; }

# Classify an install: managed-by-this-repo, external, or unknown.
#   $1 provenance file, $2 installed payload dir ("" if unknown)
# Echoes one of: managed | external | unknown
install_origin() {
  local prov="$1" root
  if [ -f "$prov" ]; then
    root="$(read_provenance_field "$prov" repo_root 2>/dev/null || echo '')"
    if [ -n "$root" ] && [ "$root" = "$REPO_ROOT" ]; then
      printf 'managed\n'; return 0
    fi
    printf 'external\n'; return 0
  fi
  printf 'unknown\n'
}

# Compare installed payload against this repo.
#   Echoes: up-to-date | update-available | unknown
sync_state() {  # sync_state <installed-payload-dir>
  local dir="$1" a b
  [ -n "$dir" ] && [ -d "$dir" ] || { printf 'unknown\n'; return 0; }
  a="$(repo_fingerprint 2>/dev/null || echo '')"
  b="$(payload_fingerprint "$dir" 2>/dev/null || echo '')"
  if [ -z "$a" ] || [ -z "$b" ]; then printf 'unknown\n'; return 0; fi
  if [ "$a" = "$b" ]; then printf 'up-to-date\n'; else printf 'update-available\n'; fi
}

# Where Claude's installed copy of the skill payload lives, if discoverable.
claude_installed_payload_dir() {
  local base
  base="$(claude_plugin_install_path 2>/dev/null || true)"
  [ -n "$base" ] || return 1
  if [ -f "$base/skills/$SKILL_NAME/SKILL.md" ]; then
    printf '%s\n' "$base/skills/$SKILL_NAME"; return 0
  fi
  if [ -f "$base/SKILL.md" ]; then printf '%s\n' "$base"; return 0; fi
  return 1
}

codex_permanent_on() {
  local f; f="$(codex_home)/AGENTS.md"
  [ -f "$f" ] && grep -qF "<!-- ${SKILL_NAME}:always-on:begin -->" "$f" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Source (marketplace origin) resolution
# ---------------------------------------------------------------------------

# Infer preferred source from this repo's origin remote, without modifying it.
detect_repo_source() {
  local url=""
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  fi
  case "$url" in
    *github.com*)  printf 'github\n' ;;
    *git.skea.io*) printf 'gitea\n'  ;;
    *)             printf 'auto\n'   ;;
  esac
}

source_url_for() {
  case "$1" in
    gitea)  printf '%s\n' "$GITEA_URL"  ;;
    github) printf '%s\n' "$GITHUB_URL" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Skill payload validation (used before any destructive step)
# ---------------------------------------------------------------------------

validate_skill_payload() {
  local dir="$1"
  [ -f "$dir/SKILL.md" ] || { err "missing SKILL.md in $dir"; return 1; }
  [ -f "$dir/agents/openai.yaml" ] || { err "missing agents/openai.yaml in $dir"; return 1; }
  grep -q '^name: *'"$SKILL_NAME"'[[:space:]]*$' "$dir/SKILL.md" \
    || { err "SKILL.md name field is not '$SKILL_NAME'"; return 1; }
  # The opt-in invariant must survive every deployment path.
  grep -Eq '^[[:space:]]*allow_implicit_invocation:[[:space:]]*false[[:space:]]*$' "$dir/agents/openai.yaml" \
    || { err "agents/openai.yaml must set allow_implicit_invocation: false"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Claude Code operations
# ---------------------------------------------------------------------------

claude_add_marketplace() {
  local requested="$1" cli="$2"
  local candidates=() src url

  if [ "$requested" = "auto" ]; then
    local detected; detected="$(detect_repo_source)"
    case "$detected" in
      github) candidates=(github gitea) ;;
      gitea)  candidates=(gitea github) ;;
      *)      candidates=(gitea github) ;;
    esac
  else
    candidates=("$requested")
  fi

  if claude_marketplace_present; then
    ok "marketplace '$MARKETPLACE_NAME' already configured (left as-is)"
    return 0
  fi

  for src in "${candidates[@]}"; do
    url="$(source_url_for "$src")" || continue
    step "adding marketplace from $src ($url)"
    if claude_marketplace_cmd add "$url" >/dev/null 2>&1; then
      ok "marketplace added from $src"
      return 0
    fi
    if [ "$requested" != "auto" ]; then
      err "could not add marketplace from forced source '$src' ($url)"
      return 1
    fi
    warn "source '$src' unreachable, trying next"
  done

  err "could not add marketplace from any source"
  return 1
}

claude_install() {
  local source_pref="$1" permanent="$2"
  local cli
  cli="$(find_claude_cli)" || { record_fail "claude" "CLI not found"; return 1; }

  step "Claude Code: installing $SKILL_NAME"
  dim "  cli: $cli"

  # Adapt to whatever subcommand names this CLI advertises before driving it.
  local missing; missing="$(claude_missing_capabilities)"
  if [ -n "$missing" ]; then
    err "Claude Code CLI interface changed: cannot find the subcommands this installer needs."
    err "  missing: $missing"
    info "  This usually means the CLI reorganised its commands. Install manually with the"
    info "  commands shown in INSTALL.md, or update this tool."
    record_fail "claude" "CLI interface changed ($missing)"
    return 1
  fi

  claude_add_marketplace "$source_pref" "$cli" || { record_fail "claude" "marketplace setup failed"; return 1; }

  if ! claude_plugin_cmd install "$PLUGIN_ID" >/dev/null 2>&1; then
    record_fail "claude" "plugin install failed"
    return 1
  fi

  if claude_plugin_installed; then
    ok "plugin installed ($PLUGIN_ID $(claude_plugin_version 2>/dev/null || echo '?'))"
    write_provenance "$(CLAUDE_PROVENANCE_FILE)" "marketplace:$source_pref"
  else
    record_fail "claude" "plugin not present after install"
    return 1
  fi

  if [ "$permanent" = "yes" ]; then
    claude_enable || { record_fail "claude" "enable failed"; return 1; }
  fi

  record_ok "claude" "installed (invoke with /$SKILL_NAME)"
  return 0
}

claude_update() {
  local source_pref="$1"
  local cli
  cli="$(find_claude_cli)" || { record_fail "claude" "CLI not found"; return 1; }

  if ! claude_plugin_installed; then
    err "Claude Code: $SKILL_NAME is not installed — run 'skills.sh install' first"
    record_fail "claude" "not installed"
    return 1
  fi

  step "Claude Code: updating $SKILL_NAME"
  # Refresh the catalog, then update the plugin. The marketplace keeps whatever
  # source it was configured with unless the caller forced one.
  if [ "$source_pref" != "auto" ] && ! claude_marketplace_present; then
    claude_add_marketplace "$source_pref" "$cli" || { record_fail "claude" "marketplace setup failed"; return 1; }
  fi

  claude_marketplace_cmd update "$MARKETPLACE_NAME" >/dev/null 2>&1 \
    || warn "marketplace refresh reported a problem; continuing to plugin update"

  if claude_plugin_cmd update "$PLUGIN_ID" >/dev/null 2>&1; then
    ok "plugin updated ($(claude_plugin_version 2>/dev/null || echo '?')) — restart Claude Code to apply"
    write_provenance "$(CLAUDE_PROVENANCE_FILE)" "marketplace:$source_pref"
    record_ok "claude" "updated"
    return 0
  fi

  record_fail "claude" "plugin update failed"
  return 1
}

claude_uninstall() {
  local remove_marketplace="$1"
  local cli
  cli="$(find_claude_cli)" || { record_fail "claude" "CLI not found"; return 1; }

  step "Claude Code: uninstalling $SKILL_NAME"

  # Permanent mode off first, so no stale flag is left behind.
  claude_disable_quiet

  if claude_plugin_installed; then
    if claude_plugin_cmd uninstall "$SKILL_NAME" >/dev/null 2>&1; then
      ok "plugin uninstalled"
    else
      record_fail "claude" "plugin uninstall failed"
      return 1
    fi
  else
    ok "plugin was not installed (nothing to do)"
  fi
  remove_provenance "$(CLAUDE_PROVENANCE_FILE)"

  if [ "$remove_marketplace" = "yes" ]; then
    local others
    others="$(claude_other_plugins_in_marketplace || true)"
    if [ -n "$others" ]; then
      err "refusing to remove marketplace '$MARKETPLACE_NAME': still used by:"
      while IFS= read -r other; do
        [ -n "$other" ] && printf '        %s\n' "$other" >&2
      done <<<"$others"
      record_fail "claude" "marketplace still in use"
      return 1
    fi
    if claude_marketplace_present; then
      if claude_marketplace_cmd remove "$MARKETPLACE_NAME" >/dev/null 2>&1; then
        ok "marketplace '$MARKETPLACE_NAME' removed"
      else
        record_fail "claude" "marketplace removal failed"
        return 1
      fi
    else
      ok "marketplace was not configured"
    fi
  fi

  record_ok "claude" "uninstalled"
  return 0
}

claude_enable() {
  local flag; flag="$(claude_flag_file)"
  mkdir -p -- "$(dirname -- "$flag")"
  if [ -f "$flag" ]; then
    ok "Claude Code: permanent mode already enabled"
  else
    : > "$flag"
    ok "Claude Code: permanent mode enabled ($flag)"
  fi
  return 0
}

claude_disable_quiet() {
  local flag; flag="$(claude_flag_file)"
  [ -f "$flag" ] && rm -f -- "$flag"
  return 0
}

claude_disable() {
  local flag; flag="$(claude_flag_file)"
  if [ -f "$flag" ]; then
    rm -f -- "$flag"
    ok "Claude Code: permanent mode disabled"
  else
    ok "Claude Code: permanent mode already disabled"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Codex operations (direct-copy route, atomic with rollback)
# ---------------------------------------------------------------------------

codex_install_payload() {
  local dest backup staging parent rc
  dest="$(codex_skill_dir)"
  parent="$(dirname -- "$dest")"

  validate_skill_payload "$SKILL_SRC" || return 1

  mkdir -p -- "$parent"

  # Stage as a sibling of the destination so the final move is same-filesystem
  # and therefore atomic.
  staging="$(mktemp -d -- "$parent/.${SKILL_NAME}.tmp.XXXXXX")"
  backup=""
  # shellcheck disable=SC2317  # invoked via trap
  cleanup_codex() {
    [ -n "${staging:-}" ] && [ -d "$staging" ] && rm -rf -- "$staging"
    if [ -n "${backup:-}" ] && [ -d "$backup" ]; then
      # Restore only if the destination is missing (i.e. we failed mid-swap).
      if [ ! -d "$dest" ]; then mv -- "$backup" "$dest"; else rm -rf -- "$backup"; fi
    fi
  }
  trap cleanup_codex RETURN

  cp -R -- "$SKILL_SRC/." "$staging/"

  # Verify the staged copy before touching the live directory.
  if ! validate_skill_payload "$staging"; then
    err "staged copy failed validation; live install left untouched"
    return 1
  fi

  if [ -d "$dest" ]; then
    backup="$(mktemp -d -- "$parent/.${SKILL_NAME}.backup.XXXXXX")"
    rmdir -- "$backup"
    mv -- "$dest" "$backup"
  fi

  if mv -- "$staging" "$dest"; then
    staging=""
    rc=0
  else
    err "atomic swap failed"
    rc=1
  fi

  if [ "$rc" -eq 0 ] && [ -n "$backup" ] && [ -d "$backup" ]; then
    rm -rf -- "$backup"; backup=""
  fi

  chmod 755 "$dest" 2>/dev/null || true
  return "$rc"
}

codex_install() {
  local permanent="$1"
  local cli
  if ! cli="$(find_codex_cli)"; then
    record_fail "codex" "CLI not found"
    return 1
  fi

  step "Codex: installing $SKILL_NAME"
  dim "  cli: $cli"

  if ! codex_install_payload; then
    record_fail "codex" "install failed (previous version restored if present)"
    return 1
  fi

  if codex_skill_installed; then
    ok "skill installed at $(codex_skill_dir)"
    write_provenance "$(CODEX_PROVENANCE_FILE)" "direct-copy"
  else
    record_fail "codex" "skill missing after install"
    return 1
  fi

  if [ "$permanent" = "yes" ]; then
    codex_enable || { record_fail "codex" "enable failed"; return 1; }
  fi

  record_ok "codex" "installed (invoke with \$$SKILL_NAME)"
  return 0
}

codex_update() {
  if ! have_codex; then record_fail "codex" "CLI not found"; return 1; fi

  if ! codex_skill_installed; then
    err "Codex: $SKILL_NAME is not installed — run 'skills.sh install' first"
    record_fail "codex" "not installed"
    return 1
  fi

  step "Codex: updating $SKILL_NAME"
  if ! codex_install_payload; then
    record_fail "codex" "update failed (previous version restored)"
    return 1
  fi
  ok "skill updated at $(codex_skill_dir)"
  write_provenance "$(CODEX_PROVENANCE_FILE)" "direct-copy"
  record_ok "codex" "updated"
  return 0
}

codex_uninstall() {
  if ! have_codex; then record_fail "codex" "CLI not found"; return 1; fi

  step "Codex: uninstalling $SKILL_NAME"
  codex_disable_quiet

  local dest; dest="$(codex_skill_dir)"
  if [ -d "$dest" ]; then
    rm -rf -- "$dest"
    ok "removed $dest"
  else
    ok "skill was not installed (nothing to do)"
  fi
  remove_provenance "$(CODEX_PROVENANCE_FILE)"
  record_ok "codex" "uninstalled"
  return 0
}

codex_enable() {
  [ -f "$CODEX_ENABLE_SCRIPT" ] || { err "missing $CODEX_ENABLE_SCRIPT"; return 1; }
  if HOME="$HOME" CODEX_HOME="$(codex_home)" sh "$CODEX_ENABLE_SCRIPT" >/dev/null 2>&1; then
    ok "Codex: permanent mode enabled ($(codex_home)/AGENTS.md)"
    return 0
  fi
  err "Codex: failed to enable permanent mode"
  return 1
}

codex_disable_quiet() {
  [ -f "$CODEX_DISABLE_SCRIPT" ] || return 0
  HOME="$HOME" CODEX_HOME="$(codex_home)" sh "$CODEX_DISABLE_SCRIPT" >/dev/null 2>&1 || true
  return 0
}

codex_disable() {
  [ -f "$CODEX_DISABLE_SCRIPT" ] || { err "missing $CODEX_DISABLE_SCRIPT"; return 1; }
  if HOME="$HOME" CODEX_HOME="$(codex_home)" sh "$CODEX_DISABLE_SCRIPT" >/dev/null 2>&1; then
    ok "Codex: permanent mode disabled"
    return 0
  fi
  err "Codex: failed to disable permanent mode"
  return 1
}

# ---------------------------------------------------------------------------
# status / doctor
# ---------------------------------------------------------------------------

# Compare the installed Codex payload against this repo's copy.
codex_matches_repo() {
  codex_skill_installed || return 1
  local a b
  a="$(cat "$SKILL_SRC/SKILL.md" 2>/dev/null | sha256sum | cut -d' ' -f1)" || return 1
  b="$(cat "$(codex_skill_dir)/SKILL.md" 2>/dev/null | sha256sum | cut -d' ' -f1)" || return 1
  [ "$a" = "$b" ]
}

repo_head() {
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
  else
    printf 'unknown\n'
  fi
}

# Render the shared "where did this install come from / is it current" block.
#   $1 provenance file, $2 installed payload dir ("" if not discoverable)
print_version_block() {
  local prov="$1" payload_dir="$2"
  local origin sync rev

  origin="$(install_origin "$prov" "$payload_dir")"
  sync="$(sync_state "$payload_dir")"
  rev="$(read_provenance_field "$prov" repo_commit 2>/dev/null || echo '')"

  case "$origin" in
    managed)
      if [ -n "$rev" ]; then
        printf '  Installed rev:   %s\n' "${rev:0:7}"
      else
        printf '  Installed rev:   unknown\n'
      fi
      printf '  Source:          this repo (%s)\n' "$REPO_ROOT" ;;
    external)
      local other; other="$(read_provenance_field "$prov" repo_root 2>/dev/null || echo 'unknown')"
      if [ -n "$rev" ]; then
        printf '  Installed rev:   %s\n' "${rev:0:7}"
      else
        printf '  Installed rev:   unknown\n'
      fi
      printf '  Source:          External install (deployed from %s)\n' "${other:-unknown}" ;;
    *)
      printf '  Installed rev:   unknown\n'
      printf '  Source:          External install (not deployed by this tool)\n' ;;
  esac

  case "$sync" in
    up-to-date)       printf '  Status:          Up to date\n' ;;
    update-available) printf '  Status:          Update available\n' ;;
    *)                printf '  Status:          Unknown\n' ;;
  esac
}

cmd_status() {
  local want_claude="$1" want_codex="$2"

  printf '%s%s status%s\n\n' "$C_BOLD" "$SKILL_NAME" "$C_RESET"

  printf '%sRepository%s\n' "$C_BOLD" "$C_RESET"
  printf '  Path:            %s\n' "$REPO_ROOT"
  printf '  Commit:          %s\n' "$(repo_head)"
  local rfp; rfp="$(repo_fingerprint 2>/dev/null || echo '')"
  if [ -n "$rfp" ]; then
    printf '  Payload:         %s\n' "${rfp:0:12}"
  else
    printf '  Payload:         unknown\n'
  fi
  printf '\n'

  if [ "$want_claude" = "yes" ]; then
    printf '%sClaude Code%s\n' "$C_BOLD" "$C_RESET"
    if have_claude; then
      printf '  CLI:             installed (%s)\n' "$(claude_version_string)"
      local missing; missing="$(claude_missing_capabilities 2>/dev/null || echo 'plugin-group')"
      if [ -n "$missing" ]; then
        printf '  CLI interface:   changed (missing: %s)\n' "$missing"
        printf '  Plugin:          unknown\n'
      elif claude_plugin_installed; then
        local v; v="$(claude_plugin_version 2>/dev/null || true)"
        if claude_plugin_enabled; then
          printf '  Plugin:          installed%s\n' "${v:+ ($v)}"
        else
          printf '  Plugin:          installed but disabled%s\n' "${v:+ ($v)}"
        fi
        print_version_block "$(CLAUDE_PROVENANCE_FILE)" "$(claude_installed_payload_dir 2>/dev/null || echo '')"
      else
        printf '  Plugin:          not installed\n'
      fi
    else
      printf '  CLI:             not installed\n'
      printf '  Plugin:          unknown\n'
    fi
    if claude_permanent_on; then
      printf '  Permanent mode:  enabled\n'
    else
      printf '  Permanent mode:  disabled\n'
    fi
    printf '  Invocation:      /%s\n\n' "$SKILL_NAME"
  fi

  if [ "$want_codex" = "yes" ]; then
    printf '%sCodex%s\n' "$C_BOLD" "$C_RESET"
    if have_codex; then
      printf '  CLI:             installed (%s)\n' "$(codex_version_string)"
    else
      printf '  CLI:             not installed\n'
    fi
    if codex_skill_installed; then
      printf '  Skill:           installed\n'
      print_version_block "$(CODEX_PROVENANCE_FILE)" "$(codex_skill_dir)"
    else
      printf '  Skill:           not installed\n'
    fi
    if codex_permanent_on; then
      printf '  Permanent mode:  enabled\n'
    else
      printf '  Permanent mode:  disabled\n'
    fi
    printf '  Invocation:      $%s\n\n' "$SKILL_NAME"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

cmd_self_test() {
  local runner="$REPO_ROOT/tests/run_all.sh"

  printf 'Running self test...\n\n'

  if [ ! -f "$runner" ]; then
    err "Repository incomplete: tests/run_all.sh is missing."
    info "  Expected at: $runner"
    info "  This copy of the repository does not include its test suite. Re-clone from"
    info "  https://git.skea.io/S/skills.git (or the GitHub mirror) to get a complete checkout."
    return 1
  fi
  if [ ! -r "$runner" ]; then
    err "Repository incomplete: tests/run_all.sh is not readable."
    info "  Expected at: $runner"
    return 1
  fi

  local rc=0
  bash "$runner" || rc=$?

  printf '\n'
  if [ "$rc" -eq 0 ]; then
    printf '%sPASS%s\n' "$C_GREEN" "$C_RESET"
    return 0
  fi
  printf '%sFAIL%s (self test exited %s)\n' "$C_RED" "$C_RESET" "$rc"
  return 1
}

DOCTOR_FAIL=0
d_ok()    { printf '  %s[ ok ]%s %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
d_warn()  { printf '  %s[warn]%s %s\n'   "$C_YELLOW" "$C_RESET" "$*"; }
d_fail()  { printf '  %s[fail]%s %s\n'   "$C_RED"    "$C_RESET" "$*"; DOCTOR_FAIL=1; }
d_info()  { printf '  %s[info]%s %s\n'   "$C_DIM"    "$C_RESET" "$*"; }

cmd_doctor() {
  local want_claude="$1" want_codex="$2"

  printf '%s%s doctor%s\n\n' "$C_BOLD" "$SKILL_NAME" "$C_RESET"

  printf '%sEnvironment%s\n' "$C_BOLD" "$C_RESET"
  if [ -n "${BASH_VERSION:-}" ]; then
    case "${BASH_VERSINFO[0]}" in
      [0-2]) d_fail "bash ${BASH_VERSION} is too old (need 3+)" ;;
      *)     d_ok   "bash ${BASH_VERSION}" ;;
    esac
  else
    d_fail "not running under bash"
  fi
  if command -v git >/dev/null 2>&1; then d_ok "git $(git --version | awk '{print $3}')"
  else d_warn "git not found (only needed for repo metadata)"; fi
  if command -v jq >/dev/null 2>&1; then d_ok "jq $(jq --version 2>/dev/null)"
  else d_fail "jq not found (required to read Claude CLI JSON output)"; fi

  printf '\n%sRepository payload%s\n' "$C_BOLD" "$C_RESET"
  if validate_skill_payload "$SKILL_SRC" >/dev/null 2>&1; then
    d_ok "skill source valid ($SKILL_SRC)"
    d_ok "opt-in invariant: allow_implicit_invocation: false"
  else
    d_fail "skill source invalid or incomplete ($SKILL_SRC)"
  fi
  if grep -q '^disable-model-invocation: *true' "$SKILL_SRC/SKILL.md" 2>/dev/null; then
    d_ok "opt-in invariant: disable-model-invocation: true"
  else
    d_fail "SKILL.md must set disable-model-invocation: true"
  fi

  local f
  for f in "$REPO_ROOT/.claude-plugin/marketplace.json" \
           "$REPO_ROOT/plugins/$SKILL_NAME/.claude-plugin/plugin.json" \
           "$REPO_ROOT/plugins/$SKILL_NAME/.codex-plugin/plugin.json" \
           "$REPO_ROOT/plugins/$SKILL_NAME/hooks/hooks.json" \
           "$REPO_ROOT/.agents/plugins/marketplace.json"; do
    if [ ! -f "$f" ]; then d_fail "missing manifest: ${f#"$REPO_ROOT"/}"
    elif command -v jq >/dev/null 2>&1 && ! jq empty "$f" >/dev/null 2>&1; then
      d_fail "invalid JSON: ${f#"$REPO_ROOT"/}"
    else d_ok "manifest ok: ${f#"$REPO_ROOT"/}"; fi
  done

  for f in "$REPO_ROOT/plugins/$SKILL_NAME/hooks/always-on.sh" \
           "$CODEX_ENABLE_SCRIPT" "$CODEX_DISABLE_SCRIPT"; do
    if [ ! -f "$f" ]; then d_fail "missing script: ${f#"$REPO_ROOT"/}"
    elif [ ! -r "$f" ]; then d_fail "unreadable script: ${f#"$REPO_ROOT"/}"
    else d_ok "script present: ${f#"$REPO_ROOT"/}"; fi
  done

  d_warn "Codex plugin-route validator rejects 'disable-model-invocation: true' (documented cross-platform conflict; the direct-copy route used here is unaffected)"

  if [ "$want_claude" = "yes" ]; then
    printf '\n%sClaude Code%s\n' "$C_BOLD" "$C_RESET"
    if have_claude; then
      # A version we cannot parse is reported as unknown, never as a failure.
      d_ok "CLI: $(find_claude_cli) (version: $(claude_version_string))"

      # Capability detection, not version gating: we ask the CLI what it can do.
      local missing; missing="$(claude_missing_capabilities 2>/dev/null || echo 'plugin-group')"
      if [ -z "$missing" ]; then
        d_ok "CLI interface: '$CAP_PLUGIN_GROUP' / '$CAP_MARKETPLACE_GROUP' subcommands available"
      else
        # The CLI exists but we cannot drive it — install genuinely cannot work.
        d_fail "CLI interface changed: missing $missing"
        d_info "the installer cannot drive this CLI; install manually per INSTALL.md"
      fi

      if [ -z "$missing" ]; then
        if claude_marketplace_present; then d_ok "marketplace '$MARKETPLACE_NAME' configured"
        else d_info "marketplace '$MARKETPLACE_NAME' not configured"; fi
        if claude_plugin_installed; then
          d_ok "plugin installed ($(claude_plugin_version 2>/dev/null || echo '?'))"
          if claude_plugin_enabled; then d_ok "plugin enabled"
          else d_warn "plugin installed but disabled"; fi
          local cstate; cstate="$(sync_state "$(claude_installed_payload_dir 2>/dev/null || echo '')")"
          case "$cstate" in
            up-to-date)       d_ok   "installed copy matches this repo" ;;
            update-available) d_warn "installed copy differs from this repo (run: skills.sh update --claude)" ;;
            *)                d_info "cannot compare installed copy with this repo (unknown)" ;;
          esac
        else
          d_info "plugin not installed"
        fi
      fi

      if claude_permanent_on; then d_info "permanent mode: enabled"
      else d_info "permanent mode: disabled"; fi
    else
      # Absent CLI is a warning, not a failure: the other platform may be fine.
      d_warn "CLI not installed"
    fi
  fi

  if [ "$want_codex" = "yes" ]; then
    printf '\n%sCodex%s\n' "$C_BOLD" "$C_RESET"
    if have_codex; then
      d_ok "CLI: $(find_codex_cli) (version: $(codex_version_string))"
    else
      d_warn "CLI not installed"
    fi
    if codex_skill_installed; then
      d_ok "skill installed at $(codex_skill_dir)"
      if validate_skill_payload "$(codex_skill_dir)" >/dev/null 2>&1; then
        d_ok "installed payload valid"
      else
        d_fail "installed payload invalid"
      fi
      if codex_matches_repo; then
        d_ok "installed copy matches this repo"
      else
        d_warn "installed copy differs from this repo (run: skills.sh update --codex)"
      fi
    else
      d_info "skill not installed"
    fi
    if codex_permanent_on; then d_info "permanent mode: enabled"
    else d_info "permanent mode: disabled"; fi

    # Leftover staging/backup dirs from an interrupted install.
    local parent leftovers
    parent="$(dirname -- "$(codex_skill_dir)")"
    if [ -d "$parent" ]; then
      leftovers="$(find "$parent" -maxdepth 1 \
        \( -name ".${SKILL_NAME}.tmp.*" -o -name ".${SKILL_NAME}.backup.*" \) 2>/dev/null || true)"
      if [ -n "$leftovers" ]; then
        d_fail "leftover staging/backup directories found:"
        while IFS= read -r leftover; do
          [ -n "$leftover" ] && printf '         %s\n' "$leftover"
        done <<<"$leftovers"
      else
        d_ok "no leftover staging/backup directories"
      fi
    fi
  fi

  printf '\n%sRepository state%s\n' "$C_BOLD" "$C_RESET"
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    d_info "HEAD: $(repo_head)"
    local origin; origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo 'none')"
    d_info "origin: $origin"
    if [ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
      d_ok "working tree clean"
    else
      d_warn "working tree has uncommitted changes"
    fi
  else
    d_info "not a git checkout (ZIP export or read-only copy) — this is supported"
  fi

  printf '\n%sRemote reachability (lightweight)%s\n' "$C_BOLD" "$C_RESET"
  if command -v git >/dev/null 2>&1; then
    local u name
    for name in gitea github; do
      u="$(source_url_for "$name")"
      if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true timeout 12 git ls-remote --heads "$u" >/dev/null 2>&1; then
        d_ok "$name reachable"
      else
        d_warn "$name not reachable right now ($u)"
      fi
    done
  else
    d_warn "git not available; skipped remote probe"
  fi

  printf '\n'
  if [ "$DOCTOR_FAIL" -eq 0 ]; then
    printf '%sdoctor: all critical checks passed%s\n' "$C_GREEN" "$C_RESET"
    return 0
  fi
  printf '%sdoctor: critical problems found%s\n' "$C_RED" "$C_RESET"
  return 1
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
${C_BOLD}skills.sh${C_RESET} — lifecycle manager for the ${SKILL_NAME} Agent Skill

${C_BOLD}USAGE${C_RESET}
  bash skills.sh <command> [options]
  bash install.sh                 # shorthand for: skills.sh install

${C_BOLD}COMMANDS${C_RESET}
  install      Deploy the skill to Claude Code and/or Codex
  update       Redeploy this repo's version over an existing install
  uninstall    Remove the skill (turns permanent mode off first)
  enable       Turn on permanent mode (applies to every new session)
  disable      Turn off permanent mode (skill stays installed)
  status       Read-only report of what is installed and enabled
  doctor       Read-only diagnostics
  self-test    Run this repository's full test suite
  help         Show this help

${C_BOLD}PLATFORM${C_RESET}
  --claude     Claude Code only
  --codex      Codex only
  --all        Both platforms
               (omit to auto-detect; explicitly named platforms are never
                skipped silently)

${C_BOLD}INSTALL / UPDATE OPTIONS${C_RESET}
  --permanent        Turn on permanent mode after installing
  --no-permanent     Keep on-demand invocation (default, non-interactive)
  --source auto      Prefer this repo's origin, fall back to the other (default)
  --source gitea     Force ${GITEA_URL}
  --source github    Force ${GITHUB_URL}
                     (forced sources never fall back)

${C_BOLD}UNINSTALL OPTIONS${C_RESET}
  --remove-marketplace   Also remove the '${MARKETPLACE_NAME}' marketplace from
                         Claude Code, but only if no other plugin still uses it

${C_BOLD}INVOCATION${C_RESET}
  Claude Code:  /${SKILL_NAME}
  Codex:        \$${SKILL_NAME}

  The skill is opt-in: installing it changes nothing until you invoke it, or
  until you turn on permanent mode yourself.

${C_BOLD}NOTES${C_RESET}
  'update' redeploys the copy in this repository. It never runs git pull, so it
  works from a Gitea clone, a GitHub clone, a ZIP export, or a read-only mount.
  To get newer content, update the repository yourself and re-run it.

  Gitea (git.skea.io/S/skills) is the authoritative source.
  GitHub (github.com/eynov/skills) is a read-only distribution mirror.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

main() {
  local command="" platform="" permanent="" source_pref="auto"
  local remove_marketplace="no" want_help="no"

  [ "$#" -gt 0 ] || { usage; return 0; }

  case "$1" in
    -h|--help|help) usage; return 0 ;;
    install|update|uninstall|enable|disable|status|doctor|self-test) command="$1"; shift ;;
    -*) err "unknown option: $1"; info "Run 'bash skills.sh help' for usage."; return 2 ;;
    *)  err "unknown command: $1"; info "Run 'bash skills.sh help' for usage."; return 2 ;;
  esac

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --claude|--codex|--all)
        local p="${1#--}"
        if [ -n "$platform" ] && [ "$platform" != "$p" ]; then
          err "conflicting platform options: --$platform and --$p"; return 2
        fi
        platform="$p"; shift ;;
      --permanent)
        [ "$permanent" = "no" ] && { err "conflicting options: --permanent and --no-permanent"; return 2; }
        permanent="yes"; shift ;;
      --no-permanent)
        [ "$permanent" = "yes" ] && { err "conflicting options: --permanent and --no-permanent"; return 2; }
        permanent="no"; shift ;;
      --source)
        [ "$#" -ge 2 ] || { err "--source requires a value (auto|gitea|github)"; return 2; }
        case "$2" in
          auto|gitea|github) source_pref="$2" ;;
          *) err "invalid --source '$2' (expected auto, gitea, or github)"; return 2 ;;
        esac
        shift 2 ;;
      --source=*)
        local v="${1#--source=}"
        case "$v" in
          auto|gitea|github) source_pref="$v" ;;
          *) err "invalid --source '$v' (expected auto, gitea, or github)"; return 2 ;;
        esac
        shift ;;
      --remove-marketplace) remove_marketplace="yes"; shift ;;
      -h|--help) want_help="yes"; shift ;;
      *) err "unknown option for '$command': $1"; info "Run 'bash skills.sh help' for usage."; return 2 ;;
    esac
  done

  if [ "$want_help" = "yes" ]; then usage; return 0; fi

  # --remove-marketplace only means anything for uninstall.
  if [ "$remove_marketplace" = "yes" ] && [ "$command" != "uninstall" ]; then
    err "--remove-marketplace is only valid for 'uninstall'"; return 2
  fi

  # ---- resolve target platforms -------------------------------------------
  local want_claude="no" want_codex="no" explicit="no"
  # self-test validates the repository itself; it has no per-platform variant.
  if [ "$command" = "self-test" ]; then
    if [ -n "$platform" ]; then
      err "self-test does not take a platform option (--$platform)"
      return 2
    fi
    cmd_self_test
    return "$?"
  fi
  case "$platform" in
    claude) want_claude="yes"; explicit="yes" ;;
    codex)  want_codex="yes";  explicit="yes" ;;
    all)    want_claude="yes"; want_codex="yes"; explicit="yes" ;;
    "")
      case "$command" in
        status|doctor)
          want_claude="yes"; want_codex="yes" ;;
        install)
          have_claude && want_claude="yes"
          have_codex  && want_codex="yes"
          if [ "$want_claude" = "no" ] && [ "$want_codex" = "no" ]; then
            err "neither Claude Code nor Codex was found on this system."
            info "Install one of them first; this tool will not install a CLI for you."
            info "Looked for 'claude' and 'codex' on PATH and in common standalone locations."
            return 1
          fi ;;
        update|uninstall)
          claude_plugin_installed && want_claude="yes"
          codex_skill_installed   && want_codex="yes"
          if [ "$want_claude" = "no" ] && [ "$want_codex" = "no" ]; then
            err "$SKILL_NAME does not appear to be installed for either platform."
            info "Run 'bash skills.sh install' first, or name a platform explicitly."
            return 1
          fi ;;
        enable|disable)
          have_claude && want_claude="yes"
          have_codex  && want_codex="yes"
          # Fall back to whatever is actually installed, even if the CLI moved.
          claude_permanent_on && want_claude="yes"
          codex_skill_installed && want_codex="yes"
          if [ "$want_claude" = "no" ] && [ "$want_codex" = "no" ]; then
            err "no supported platform detected."
            info "Name a platform explicitly with --claude or --codex."
            return 1
          fi ;;
      esac ;;
  esac

  # Explicitly requested platforms must never be silently skipped.
  if [ "$explicit" = "yes" ] && [ "$command" != "status" ] && [ "$command" != "doctor" ]; then
    if [ "$want_claude" = "yes" ] && ! have_claude; then
      err "--claude was requested but the Claude Code CLI was not found."
      return 1
    fi
    if [ "$want_codex" = "yes" ] && ! have_codex; then
      err "--codex was requested but the Codex CLI was not found."
      return 1
    fi
  fi

  # ---- permanent-mode decision (install only) ------------------------------
  if [ "$command" = "install" ] && [ -z "$permanent" ]; then
    if [ -t 0 ]; then
      local answer=""
      printf 'Enable %s permanently? [y/N]: ' "$SKILL_NAME"
      IFS= read -r answer || answer=""
      case "$answer" in
        [yY]|[yY][eE][sS]) permanent="yes" ;;
        *) permanent="no" ;;
      esac
    else
      permanent="no"
    fi
  fi
  [ -n "$permanent" ] || permanent="no"

  # ---- dispatch ------------------------------------------------------------
  case "$command" in
    install)
      [ "$want_claude" = "yes" ] && { claude_install "$source_pref" "$permanent" || true; }
      [ "$want_codex"  = "yes" ] && { codex_install "$permanent" || true; }
      print_summary
      if [ "$RESULT_FAILED" -eq 0 ]; then
        printf '\nInvoke it once with: '
        [ "$want_claude" = "yes" ] && printf '/%s (Claude Code) ' "$SKILL_NAME"
        [ "$want_codex"  = "yes" ] && printf '$%s (Codex)' "$SKILL_NAME"
        printf '\n'
        if [ "$permanent" = "yes" ]; then
          info "Permanent mode is ON. Turn it off with: bash skills.sh disable"
        else
          info "Permanent mode is off (default). Turn it on with: bash skills.sh enable"
        fi
      fi
      return "$RESULT_FAILED" ;;
    update)
      [ "$want_claude" = "yes" ] && { claude_update "$source_pref" || true; }
      [ "$want_codex"  = "yes" ] && { codex_update || true; }
      print_summary
      return "$RESULT_FAILED" ;;
    uninstall)
      [ "$want_claude" = "yes" ] && { claude_uninstall "$remove_marketplace" || true; }
      [ "$want_codex"  = "yes" ] && { codex_uninstall || true; }
      print_summary
      return "$RESULT_FAILED" ;;
    enable)
      local rc=0
      [ "$want_claude" = "yes" ] && { claude_enable || rc=1; }
      [ "$want_codex"  = "yes" ] && { codex_enable  || rc=1; }
      return "$rc" ;;
    disable)
      local rc=0
      [ "$want_claude" = "yes" ] && { claude_disable || rc=1; }
      [ "$want_codex"  = "yes" ] && { codex_disable  || rc=1; }
      return "$rc" ;;
    status) cmd_status "$want_claude" "$want_codex"; return 0 ;;
    doctor) cmd_doctor "$want_claude" "$want_codex"; return "$?" ;;
    self-test) cmd_self_test; return "$?" ;;
  esac
}

main "$@"
