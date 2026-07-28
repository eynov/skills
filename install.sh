#!/usr/bin/env bash
#
# install.sh — convenience wrapper.
#
# This is deliberately a thin shim with no install logic of its own: it forwards
# to `skills.sh install` so there is only ever one implementation to maintain.
#
#   bash install.sh                 ==  bash skills.sh install
#   bash install.sh --all           ==  bash skills.sh install --all
#   bash install.sh --permanent     ==  bash skills.sh install --permanent
#
# For update / uninstall / enable / disable / status / doctor, use skills.sh.

set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
  link_target="$(readlink "$SCRIPT_PATH")"
  case "$link_target" in
    /*) SCRIPT_PATH="$link_target" ;;
    *)  SCRIPT_PATH="$(dirname -- "$SCRIPT_PATH")/$link_target" ;;
  esac
done
HERE="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

if [ ! -f "$HERE/skills.sh" ]; then
  printf 'install.sh: cannot find skills.sh next to this script (%s)\n' "$HERE" >&2
  exit 1
fi

exec bash "$HERE/skills.sh" install "$@"
