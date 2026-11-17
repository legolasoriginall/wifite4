#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — حذف کامل
#  استفاده: sudo bash uninstall.sh [--keep-wordlists] [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

KEEP_WORDLISTS=0
DRY_RUN=0

# shellcheck disable=SC1091
. "$(dirname "$0")/install/common.sh"

usage() {
  cat <<'EOF'
حذف کامل wifite4 از سیستم.

استفاده:
  sudo bash uninstall.sh                 حذف همه‌چیز (autopwn-ng، hostapd-mana، وردلیست‌ها)
  sudo bash uninstall.sh --keep-wordlists  حفظ وردلیست‌ها در /opt/wordlists
  bash uninstall.sh --dry-run            فقط نمایش آنچه حذف می‌شود
  bash uninstall.sh --help              همین راهنما

حذف می‌شود:
  /usr/local/bin/autopwn-ng, hostapd-mana
  /opt/hostapd-mana
  /opt/wordlists (مگر --keep-wordlists)
  /usr/share/hashcat/rules/OneRuleToRuleThemAll.rule

بسته‌های apt حذف نمی‌شوند — برای حذف دستی:
  sudo apt-get remove --purge aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 bettercap
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --keep-wordlists) KEEP_WORDLISTS=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "گزینه‌ی ناشناخته: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- root
ensure_root "$@"

# ---------------------------------------------------------------- log
if (( DRY_RUN == 0 )); then
  mkdir -p /var/log 2>/dev/null || true
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

remove "/usr/local/bin/autopwn-ng" "autopwn-ng"
remove "/usr/local/bin/hostapd-mana" "hostapd-mana"
remove "/opt/hostapd-mana" "hostapd-mana source/build"

if (( KEEP_WORDLISTS == 0 )); then
  remove "/opt/wordlists" "wordlists, SecLists, Probable-Wordlists"
else
  warn "وردلیست‌ها حفظ شدند (--keep-wordlists)."
fi

remove "/usr/share/hashcat/rules/OneRuleToRuleThemAll.rule" "hashcat rule"

if (( DRY_RUN == 0 )); then
  ok "حذف کامل شد."
fi