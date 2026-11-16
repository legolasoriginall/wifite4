#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — نصب autopwn-ng در /usr/local/bin
#  استفاده: sudo bash install-autopwn-ng.sh [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

DRY_RUN=0

if [[ -t 1 ]]; then
  c_reset=$'\033[0m' c_ok=$'\033[32m' c_warn=$'\033[33m' c_err=$'\033[31m' c_info=$'\033[36m'
else
  c_reset='' c_ok='' c_warn='' c_err='' c_info=''
fi

say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*"; }
die()  { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
نصب autopwn-ng در /usr/local/bin/autopwn-ng.

استفاده:
  sudo bash install-autopwn-ng.sh            نصب autopwn-ng
  bash install-autopwn-ng.sh --dry-run      فقط بررسی پیش‌نیازها، بدون تغییر
  bash install-autopwn-ng.sh --help         همین راهنما
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "گزینه‌ی ناشناخته: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- prerequisite checks
command -v bash   >/dev/null 2>&1 || die "bash پیدا نشد."
command -v chmod  >/dev/null 2>&1 || die "chmod پیدا نشد."
command -v rm     >/dev/null 2>&1 || die "rm پیدا نشد."
command -v install >/dev/null 2>&1 || die "install (coreutils) پیدا نشد."

# ---------------------------------------------------------------- root
if (( EUID != 0 )); then
  if (( DRY_RUN == 1 )); then
    warn "dry-run بدون root اجرا می‌شود؛ نصب واقعی به root نیاز دارد."
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    say "دسترسی root لازم است؛ اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "$@"
  else
    die "این اسکریپت به root نیاز دارد: sudo bash install-autopwn-ng.sh"
  fi
fi

# ---------------------------------------------------------------- source-file validation
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

[[ -f "$SRC" ]] || die "فایل منبع پیدا نشد: $SRC"
bash -n "$SRC" || die "خطای سینتکس در $SRC"

# ---------------------------------------------------------------- install
if (( DRY_RUN == 1 )); then
  warn "dry-run: install -m 755 $SRC $DEST"
else
  install -m 755 "$SRC" "$DEST"
  ok "autopwn-ng نصب شد: $DEST"
  say "اجرا: sudo autopwn-ng --help"
fi