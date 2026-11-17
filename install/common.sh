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

die()  { printf '%s[-]%s %s\n' "$_c_err"   "$_c_reset" "$*" >&2; exit 1; }
say()  { printf '%s[*]%s %s\n' "$_c_info" "$_c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$_c_ok"   "$_c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$_c_warn" "$_c_reset" "$*" >&2; }

# Require root unless WIFITE4_TEST_MODE=1; re-exec with sudo when possible.
ensure_root() {
  if [[ "${WIFITE4_TEST_MODE:-0}" == "1" ]]; then return 0; fi
  if (( EUID == 0 )); then return 0; fi
  if (( DRY_RUN == 1 )); then
    warn "dry-run بدون root اجرا می‌شود؛ نصب واقعی به root نیاز دارد."
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    say "دسترسی root لازم است؛ اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "$@"
  fi
  die "این اسکریپت به root نیاز دارد: sudo bash $0"
}

# Require root (no sudo re-exec) unless WIFITE4_TEST_MODE=1.
require_root() {
  if [[ "${WIFITE4_TEST_MODE:-0}" == "1" ]]; then return 0; fi
  (( EUID == 0 )) || die "به root نیاز دارد: sudo bash $0"
}

# Clone a git repo into dir, or replace it if a previous clone was partial/invalid.
clone_or_replace() {
  local dir="$1" url="$2"
  if [ ! -d "$dir/.git" ] || ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    rm -rf "$dir"
    git clone --depth 1 --single-branch "$url" "$dir"
  fi
}