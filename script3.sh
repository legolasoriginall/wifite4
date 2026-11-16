#!/usr/bin/env bash
# ==========================================================================
#  منوی تعاملی اجرای autopwn-ng
#  استفاده: sudo bash script3.sh
# ==========================================================================
set -uo pipefail

# ---------------------------------------------------------------- colors
if [[ -t 1 ]]; then
  c_reset=$'\033[0m' c_ok=$'\033[32m' c_warn=$'\033[33m' c_err=$'\033[31m' c_info=$'\033[36m' c_bold=$'\033[1m'
else
  c_reset='' c_ok='' c_warn='' c_err='' c_info='' c_bold=''
fi

say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*" >&2; }
err()  { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*"; }

# ---------------------------------------------------------------- prerequisite checks
die() { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*" >&2; exit 1; }

command -v iw  >/dev/null 2>&1 || die "iw پیدا نشد. ابتدا نصب کن: sudo apt-get install -y iw"
command -v awk >/dev/null 2>&1 || die "awk پیدا نشد."

# ---------------------------------------------------------------- root check
(( EUID == 0 )) || die "این اسکریپت باید با sudo اجرا شود: sudo bash script3.sh"

# ---------------------------------------------------------------- check autopwn-ng
if ! command -v autopwn-ng >/dev/null 2>&1; then
  err "autopwn-ng در PATH پیدا نشد. ابتدا نصب کنید:"
  echo "  sudo bash setup.sh  # یا: sudo install -m 755 autopwn-ng.sh /usr/local/bin/autopwn-ng"
  exit 1
fi

# ---------------------------------------------------------------- menu
show_menu() {
  echo
  printf '%s╔══════════════════════════════════════╗%s\n' "$c_bold" "$c_reset"
  printf '%s║   منوی اجرای autopwn-ng              ║%s\n' "$c_bold" "$c_reset"
  printf '%s╠══════════════════════════════════════╣%s\n' "$c_bold" "$c_reset"
  printf '%s║  1) اجرا (انتخاب پروفایل)            ║%s\n' "$c_info" "$c_reset"
  printf '%s║  2) هدف مشخص (target BSSID)           ║%s\n' "$c_info" "$c_reset"
  printf '%s║  3) اسکن سریع (no-twin/no-post)       ║%s\n' "$c_info" "$c_reset"
  printf '%s║  4) dry-run / simulate                ║%s\n' "$c_info" "$c_reset"
  printf '%s║  5) یک کلیک (auto) — اسکن+کرک+گزارش  ║%s\n' "$c_ok" "$c_reset"
  printf '%s║  0) خروج                              ║%s\n' "$c_warn" "$c_reset"
  printf '%s╚══════════════════════════════════════╝%s\n' "$c_bold" "$c_reset"
  echo
}

# ---------------------------------------------------------------- read iface
read_iface() {
  local default_iface default_iface2
  default_iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
  read -rp "اینترفیس اصلی [-i] (پیش‌فرض: ${default_iface:-wlan1}): " IFACE
  IFACE="${IFACE:-${default_iface:-wlan1}}"

  default_iface2=$(iw dev 2>/dev/null | awk -v skip="$IFACE" '/Interface/ && $2 != skip {print $2; exit}')
  read -rp "اینترفیس دوم [-I] برای evil twin (پیش‌فرض: ${default_iface2:-}): " IFACE2
  IFACE2="${IFACE2:-$default_iface2}"
}

# ---------------------------------------------------------------- run autopwn-ng with optional second iface
run_ap() {
  # All args passed through; -I added automatically if IFACE2 is set
  if [[ -n "${IFACE2:-}" ]]; then
    autopwn-ng -i "$IFACE" -I "$IFACE2" "$@"
  else
    autopwn-ng -i "$IFACE" "$@"
  fi
}

# ---------------------------------------------------------------- main loop
while true; do
  show_menu
  read -rp "انتخاب کنید [0-5]: " choice

  case "$choice" in
    1)
      read_iface
      read -rp "پروفایل (normal/stealth/brute) [normal]: " prof
      prof="${prof:-normal}"
      say "اجرای $prof..."
      run_ap -p "$prof"
      ;;
    2)
      read_iface
      read -rp "BSSID هدف: " target
      [[ -z "$target" ]] && { warn "BSSID وارد نشد."; continue; }
      say "اجرای هدف مشخص: $target"
      run_ap --target "$target"
      ;;
    3)
      read_iface
      read -rp "مدت برداشت به ثانیه (پیش‌فرض 90): " t
      t="${t:-90}"
      say "اجرای بدون فازهای بلند (no-twin, no-post, t=$t)..."
      run_ap --no-twin --no-post -t "$t"
      ;;
    4)
      say "شبیه‌سازی (بدون ابزار و تغییر روی سیستم)..."
      autopwn-ng --dry-run
      ;;
    5)
      read_iface
      say "حالت یک کلیک (auto): اسکن + انتخاب هدف + کرک + گزارش..."
      run_ap --auto
      ;;
    0)
      say "خروج."
      exit 0
      ;;
    *)
      warn "انتخاب نامعتبر: $choice"
      ;;
  esac

  echo
  read -rp "Enter برای ادامه..." _
done
