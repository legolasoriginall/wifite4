# shellcheck shell=bash
# ==========================================================================
#  wifite4 — shared helpers for install scripts
#  Source this file: . "$(dirname "$0")/common.sh"
# ==========================================================================

if [[ -t 1 ]]; then
  _c_reset=$'\033[0m' _c_ok=$'\033[32m' _c_warn=$'\033[33m' _c_err=$'\033[31m' _c_info=$'\033[36m'
else
  _c_reset='' _c_ok='' _c_warn='' _c_err='' _c_info=''
fi

die() { printf '%s[-]%s %s\n' "$_c_err" "$_c_reset" "$*" >&2; exit 1; }

# Clone a git repo into dir, or replace it if a previous clone was partial/invalid.
clone_or_replace() {
  local dir="$1" url="$2"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --depth 1 --single-branch "$url" "$dir"
  fi
}