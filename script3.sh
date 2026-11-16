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
  c_reset= c_ok= c_warn= c_err= c_info= c_bold=
fi

say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*"; }
err()  { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*"; }

# ---------------------------------------------------------------- prerequisite checks
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

command -v bash >/dev/null 2>&1 || die "bash پیدا نشد."
command -v sudo >/dev/null 2>&1 || die "sudo پیدا نشد."
command -v iw >/dev/null 2>&1 || die "iw پیدا نشد. ابتدا نصب کن: sudo apt-get install -y iw"
command -v awk >/dev/null 2>&1 || die "awk پیدا نشد."
command -v grep >/dev/null 2>&1 || die "grep پیدا نشد."

# ---------------------------------------------------------------- root check
if (( EUID != 0 )); then
  err "این اسکریپت باید با sudo اجرا شود."
  echo "  sudo bash script3.sh"
  exit 1
fi

# ---------------------------------------------------------------- check autopwn-ng
if ! command -v autopwn-ng >/dev/null 2>&1; then
  err "autopwn-ng در PATH پیدا نشد. ابتدا نصب کنید:"
  echo "  sudo bash install/04-install-autopwn-ng.sh"
  exit 1
fi

# ---------------------------------------------------------------- menu
show_menu() {
  echo
  printf '%s╔══════════════════════════════════════╗%s\n' "$c_bold" "$c_reset"
  printf '%s║   منوی اجرای autopwn-ng              ║%s\n' "$c_bold" "$c_reset"
  printf '%s╠══════════════════════════════════════╣%s\n' "$c_bold" "$c_reset"
  printf '%s║  1) پیش‌فرض (normal)                  ║%s\n' "$c_info" "$c_reset"
  printf '%s║  2) stealth (مخفی، MAC رندوم)         ║%s\n' "$c_info" "$c_reset"
  printf '%s║  3) brute (تهاجمی، workload بالا)     ║%s\n' "$c_info" "$c_reset"
  printf '%s║  4) هدف مشخص (target BSSID)           ║%s\n' "$c_info" "$c_reset"
  printf '%s║  5) بدون فازهای بلند (no-twin/no-post)║%s\n' "$c_info" "$c_reset"
  printf '%s║  6) dry-run / simulate                ║%s\n' "$c_info" "$c_reset"
  printf '%s║  0) خروج                              ║%s\n' "$c_warn" "$c_reset"
  printf '%s╚══════════════════════════════════════╝%s\n' "$c_bold" "$c_reset"
  echo
}

# ---------------------------------------------------------------- read iface
read_iface() {
  local default_iface
  default_iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
  read -rp "اینترفیس اصلی [-i] (پیش‌فرض: ${default_iface:-wlan1}): " IFACE
  IFACE="${IFACE:-${default_iface:-wlan1}}"

  local default_iface2
  default_iface2=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -vxF "$IFACE" | head -1)
  read -rp "اینترفیس دوم [-I] برای evil twin (پیش‌فرض: ${default_iface2:-}): " IFACE2
  IFACE2="${IFACE2:-$default_iface2}"
}

# ---------------------------------------------------------------- main loop
while true; do
  show_menu
  read -rp "انتخاب کنید [0-6]: " choice

  case "$choice" in
    1)
      read_iface
      say "اجرای پیش‌فرض (normal)..."
      if [[ -n "$IFACE2" ]]; then
        sudo autopwn-ng -i "$IFACE" -I "$IFACE2"
      else
        sudo autopwn-ng -i "$IFACE"
      fi
      ;;
    2)
      read_iface
      say "اجرای stealth (MAC رندوم، برداشت طولانی)..."
      sudo autopwn-ng -i "$IFACE" -p stealth
      ;;
    3)
      read_iface
      say "اجرای brute (تهاجمی، workload بالا)..."
      if [[ -n "$IFACE2" ]]; then
        sudo autopwn-ng -i "$IFACE" -I "$IFACE2" -p brute
      else
        sudo autopwn-ng -i "$IFACE" -p brute
      fi
      ;;
    4)
      read_iface
      read -rp "BSSID هدف: " target
      [[ -z "$target" ]] && { warn "BSSID وارد نشد."; continue; }
      say "اجرای هدف مشخص: $target"
      if [[ -n "$IFACE2" ]]; then
        sudo autopwn-ng -i "$IFACE" -I "$IFACE2" --target "$target"
      else
        sudo autopwn-ng -i "$IFACE" --target "$target"
      fi
      ;;
    5)
      read_iface
      read -rp "مدت برداشت به ثانیه (پیش‌فرض 90): " t
      t="${t:-90}"
      say "اجرای بدون فازهای بلند (no-twin, no-post, t=$t)..."
      sudo autopwn-ng -i "$IFACE" --no-twin --no-post -t "$t"
      ;;
    6)
      say "شبیه‌سازی (بدون ابزار و تغییر روی سیستم)..."
      sudo autopwn-ng --dry-run
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
