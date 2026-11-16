#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — نصب سریع (بدون وردلیست‌ها)
#  اجرا: sudo bash install-all.sh [--dry-run] [--help]
#  مراحل: 01-install-packages → 02-build-hostapd-mana → نصب autopwn-ng
# ==========================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

DRY_RUN=0

if [[ -t 1 ]]; then
  c_reset=$'\033[0m' c_ok=$'\033[32m' c_warn=$'\033[33m' c_err=$'\033[31m' c_info=$'\033[36m'
else
  c_reset='' c_ok='' c_warn='' c_err='' c_info=''
fi

die() { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*" >&2; exit 1; }
say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$REPO_DIR/install/01-install-packages.sh" ]] || die "install/01-install-packages.sh پیدا نشد."
[[ -f "$REPO_DIR/install/02-build-hostapd-mana.sh" ]] || die "install/02-build-hostapd-mana.sh پیدا نشد."
[[ -f "$REPO_DIR/autopwn-ng.sh" ]] || die "autopwn-ng.sh پیدا نشد."

usage() {
  cat <<'EOF'
نصب سریع wifite4 بدون دانلود وردلیست‌ها.

استفاده:
  sudo bash install-all.sh                 نصب کامل (بسته‌ها + hostapd-mana + autopwn-ng)
  bash install-all.sh --dry-run            فقط نمایش مراحل، بدون تغییر
  bash install-all.sh --help               همین راهنما

مراحل:
  1) install/01-install-packages.sh      بسته‌های پایه
  2) install/02-build-hostapd-mana.sh    ساخت و نصب hostapd-mana
  3) نصب autopwn-ng در /usr/local/bin
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
  elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
    say "اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "$@"
  else
    die "به root نیاز دارد: sudo bash install-all.sh"
  fi
fi

run_step() {
  local script="$1" title="$2"
  local path="$REPO_DIR/$script"
  [[ -f "$path" ]] || die "اسکریپت پیدا نشد: $path"
  say "── $title ──"
  if (( DRY_RUN == 1 )); then
    warn "dry-run: bash $script"
    return 0
  fi
  bash "$path" || die "مرحله شکست خورد: $script"
  ok "$title تمام شد"
}

# ---------------------------------------------------------------- main
if (( DRY_RUN == 1 )); then
  say "wifite4 — نصب سریع (dry-run)"
else
  say "wifite4 — نصب سریع (بدون وردلیست‌ها)"
fi

# مرحله ۱: بسته‌های پایه
run_step "install/01-install-packages.sh" "نصب بسته‌های پایه"

# مرحله ۲: ساخت hostapd-mana
run_step "install/02-build-hostapd-mana.sh" "ساخت و نصب hostapd-mana"

# مرحله ۳: نصب autopwn-ng (install -m 755 شامل +x است)
say "── نصب autopwn-ng ──"
SRC="$REPO_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

if (( DRY_RUN == 1 )); then
  warn "dry-run: install -m 755 $SRC $DEST"
else
  [[ -f "$SRC" ]] || die "autopwn-ng.sh پیدا نشد: $SRC"
  bash -n "$SRC" || die "خطای سینتکس در $SRC"
  install -m 755 "$SRC" "$DEST"
  ok "autopwn-ng نصب شد: $DEST"
fi

if (( DRY_RUN == 1 )); then
  ok "dry-run تمام شد — هیچ تغییری روی سیستم اعمال نشد."
else
  ok "نصب سریع کامل شد."
  say "شروع کن با: sudo autopwn-ng --help"
fi
