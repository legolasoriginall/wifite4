# shellcheck shell=bash
# ==========================================================================
#  wifite4 — shared helpers for install scripts
#  Source this file: . "$(dirname "$0")/common.sh"
# ==========================================================================

# Clone a git repo into dir, or replace it if a previous clone was partial/invalid.
clone_or_replace() {
  local dir="$1" url="$2"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --depth 1 --single-branch "$url" "$dir"
  fi
}