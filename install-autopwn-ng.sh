#!/usr/bin/env bash
# ==========================================================================
#  نصب autopwn-ng در مسیر سیستم با مجوز اجرا
#  استفاده: sudo bash install-autopwn-ng.sh [--dry-run] [--help]
#  جایگزین مرحله‌ی nano: فایل را کپی و chmod +x می‌کند
# ==========================================================================
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

DRY_RUN=0
ORIGINAL_ARGS=("$@")

if [[ -t 1 ]]; then
  c_reset=$'\033[0m' c_ok=$'\033[32m' c_warn=$'\033[33m' c_err=$'\033[31m' c_info=$'\033[36m'
else
  c_reset='' c_ok='' c_warn='' c_err='' c_info=''
fi

say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*"; }
die()  { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*"; exit 1; }

usage() {
  cat <<'EOF'
نصب autopwn-ng در /usr/local/bin با مجوز اجرا.

استفاده:
  sudo bash install-autopwn-ng.sh                 نصب و chmod +x
  bash install-autopwn-ng.sh --dry-run            پیش‌نمایش بدون تغییر
  bash install-autopwn-ng.sh --help              همین راهنما

مراحل:
  1) بررسی وجود فایل autopwn-ng.sh
  2) بررسی دسترسی root
  3) بررسی سینتکس (bash -n)
  4) حذف مقصد قبلی (در صورت وجود)
  5) کپی فایل به /usr/local/bin/autopwn-ng
  6) chmod +x (مجوز اجرا)
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

# ---------------------------------------------------------------- root
if (( EUID != 0 )); then
  if (( DRY_RUN == 1 )); then
    warn "dry-run بدون root اجرا می‌شود."
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    say "اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
  else
    die "به root نیاز دارد: sudo bash install-autopwn-ng.sh"
  fi
fi

# ---------------------------------------------------------------- main
if (( DRY_RUN == 1 )); then
  say "نصب autopwn-ng (dry-run) — هیچ تغییری اعمال نمی‌شود"
else
  say "نصب autopwn-ng در $DEST"
fi

# ۱. بررسی وجود فایل
[[ -f "$SRC" ]] || die "فایل پیدا نشد: $SRC"
say "فایل منبع: $SRC"

# ۲. بررسی سینتکس
if (( DRY_RUN == 1 )); then
  warn "dry-run: bash -n $SRC"
else
  bash -n "$SRC" || die "خطای سینتکس در $SRC"
  ok "سینتکس OK"
fi

# ۳. حذف مقصد قبلی
if (( DRY_RUN == 1 )); then
  warn "dry-run: rm -f $DEST"
else
  rm -f "$DEST"
  say "مقصد قبلی حذف شد (در صورت وجود)"
fi

# ۴. کپی فایل
if (( DRY_RUN == 1 )); then
  warn "dry-run: install -m 755 $SRC $DEST"
else
  install -m 755 "$SRC" "$DEST"
  ok "فایل کپی شد: $DEST"
fi

# ۵. مجوز اجرا
if (( DRY_RUN == 1 )); then
  warn "dry-run: chmod +x $DEST"
else
  chmod +x "$DEST"
  ok "مجوز اجرا اعمال شد (chmod +x)"
fi

# ۶. تأیید
if (( DRY_RUN == 0 )); then
  if [[ -x "$DEST" ]]; then
    ok "تأیید: $DEST قابل اجرا است"
  else
    die "خطا: $DEST قابل اجرا نیست"
  fi
  echo
  ok "نصب کامل شد."
  say "شروع کن با: sudo autopwn-ng --help"
fi
