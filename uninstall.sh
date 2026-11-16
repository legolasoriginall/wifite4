#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — حذف کامل
#  استفاده: sudo bash uninstall.sh [--keep-wordlists] [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

WITH_WORDLISTS=1
DRY_RUN=0

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
حذف کامل wifite4 از سیستم.

استفاده:
  sudo bash uninstall.sh                 حذف همه‌چیز (autopwn-ng، hostapd-mana، وردلیست‌ها)
  sudo bash uninstall.sh --keep-wordlists  حفظ وردلیست‌ها در /opt/wordlists
  bash uninstall.sh --dry-run            فقط نمایش آنچه حذف می‌شود
  bash uninstall.sh --help              همین راهنما

مراحل حذف:
  1) /usr/local/bin/autopwn-ng
  2) /usr/local/bin/hostapd-mana
  3) /usr/local/bin/kwp
  4) /opt/hostapd-mana
  5) /opt/wordlists (مگر --keep-wordlists)
  6) hashcat rules (OneRuleToRuleThemAll.rule)

گزارش حذف در /var/log/wifite4-uninstall.log ذخیره می‌شود.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --keep-wordlists) WITH_WORDLISTS=0 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "گزینه‌ی ناشناخته: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- root
if (( EUID != 0 )); then
  if (( DRY_RUN == 1 )); then
    warn "dry-run بدون root اجرا می‌شود؛ حذف واقعی به root نیاز دارد."
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    say "دسترسی root لازم است؛ اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "$@"
  else
    die "این اسکریپت به root نیاز دارد: sudo bash uninstall.sh"
  fi
fi

# ---------------------------------------------------------------- log
if (( DRY_RUN == 0 )); then
  mkdir -p "$(dirname /var/log/wifite4-uninstall.log)" 2>/dev/null || true
  exec > >(tee -a /var/log/wifite4-uninstall.log) 2>&1
  say "گزارش حذف: /var/log/wifite4-uninstall.log"
fi

# ---------------------------------------------------------------- helpers
remove() {
  local path="$1" desc="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    if (( DRY_RUN == 1 )); then
      warn "dry-run: rm -rf $path  ($desc)"
    else
      rm -rf "$path"
      ok "حذف شد: $path  ($desc)"
    fi
  else
    say "یافت نشد (رد شد): $path"
  fi
}

# ---------------------------------------------------------------- main
if (( DRY_RUN == 1 )); then
  say "wifite4 — حذف (dry-run) — هیچ تغییری اعمال نمی‌شود"
else
  say "wifite4 — حذف کامل"
fi

# --- binaries ---
remove "/usr/local/bin/autopwn-ng" "autopwn-ng"
remove "/usr/local/bin/hostapd-mana" "hostapd-mana"
remove "/usr/local/bin/kwp" "kwp"

# --- directories ---
remove_path "/opt/hostapd-mana" "hostapd-mana source/build"

if (( WITH_WORDLISTS == 1 )); then
  remove_path "/opt/wordlists" "wordlists, SecLists, Probable-Wordlists"
else
  warn "وردلیست‌ها حفظ شدند (--keep-wordlists)."
fi

# --- hashcat rules ---
remove "/usr/share/hashcat/rules/OneRuleToRuleThemAll.rule" "hashcat rule"

# --- optional: remove apt packages (ask or skip) ---
say "بسته‌های apt (aircrack-ng, hashcat, …) حذف نمی‌شوند — برای حذف دستی:"
say "  sudo apt-get remove --purge aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 bettercap"

if (( DRY_RUN == 1 )); then
  ok "dry-run تمام شد — هیچ تغییری روی سیستم اعمال نشد."
else
  ok "حذف کامل شد."
fi
