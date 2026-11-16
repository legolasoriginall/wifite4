#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — نصب کامل و خودکار
#  استفاده: sudo bash setup.sh [--full|--quick] [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wifite4-setup.log"
WITH_WORDLISTS=1
DRY_RUN=0

if [[ -t 1 ]]; then
  c_reset=$'\033[0m' c_ok=$'\033[32m' c_warn=$'\033[33m' c_err=$'\033[31m' c_info=$'\033[36m'
else
  c_reset='' c_ok='' c_warn='' c_err='' c_info=''
fi

say()  { printf '%s[*]%s %s\n' "$c_info" "$c_reset" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_reset" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_reset" "$*" >&2; }
die()  { printf '%s[-]%s %s\n' "$c_err" "$c_reset" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
نصب خودکار و ترتیبی همه‌ی مراحل wifite4.

استفاده:
  sudo bash setup.sh                 نصب کامل (پیش‌فرض: شامل وردلیست‌ها)
  sudo bash setup.sh --full          نصب کامل، شامل دانلود وردلیست‌ها
  sudo bash setup.sh --quick         نصب سریع، بدون دانلود وردلیست‌ها
  bash setup.sh --dry-run            فقط بررسی پیش‌نیازها و نمایش مراحل
  bash setup.sh --help               همین راهنما

گزینه‌ها:
  --full           شامل دانلود وردلیست‌ها (پیش‌فرض)
  --quick          بدون دانلود وردلیست‌ها (سریع‌تر)
  --no-wordlists   نام قدیمی --quick (برای سازگاری پذیرفته می‌شود)
  --dry-run        فقط بررسی پیش‌نیازها و نمایش مراحل
  --help           همین راهنما

مراحل:
  1) install/01-install-packages.sh      بسته‌های پایه
  2) install/02-build-hostapd-mana.sh    ساخت و نصب hostapd-mana
  3) install/03-download-wordlists.sh    دانلود وردلیست‌ها، ruleها و ساخت kwp (با --quick رد می‌شود)
  4) نصب autopwn-ng در /usr/local/bin

گزارش اجرا در /var/log/wifite4-setup.log ذخیره می‌شود.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --full)         WITH_WORDLISTS=1 ;;
    --quick)        WITH_WORDLISTS=0 ;;
    --no-wordlists) WITH_WORDLISTS=0 ;;  # alias for --quick
    --dry-run)      DRY_RUN=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; die "گزینه‌ی ناشناخته: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- root
if (( EUID != 0 )); then
  if (( DRY_RUN == 1 )); then
    warn "dry-run بدون root اجرا می‌شود؛ نصب واقعی به root نیاز دارد."
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    say "دسترسی root لازم است؛ اجرای مجدد با sudo…"
    exec sudo -E bash "$0" "$@"
  else
    die "این اسکریپت به root نیاز دارد: sudo bash setup.sh"
  fi
fi

# ---------------------------------------------------------------- log
if (( DRY_RUN == 0 )); then
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  exec > >(tee -a "$LOG_FILE") 2>&1
  say "گزارش اجرا: $LOG_FILE"
fi

START_TS=$SECONDS

# ---------------------------------------------------------------- checks
check_os() {
  command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد؛ این اسکریپت برای Debian/Ubuntu/Kali/Parrot است."
  ok "توزیع سازگار (apt-get موجود است)"
}

check_network() {
  local have_net=0
  # bash built-in /dev/tcp avoids depending on curl/wget for the preflight
  if timeout 10 bash -c 'exec 3<>/dev/tcp/github.com/443' 2>/dev/null; then
    have_net=1
  elif command -v wget >/dev/null 2>&1 && wget -q --spider --timeout=10 https://github.com 2>/dev/null; then
    have_net=1
  fi
  if (( have_net == 1 )); then
    ok "دسترسی به اینترنت برقرار است"
  elif (( DRY_RUN == 1 )); then
    warn "اینترنت در دسترس نیست (برای apt و دانلود وردلیست لازم است)"
  else
    die "دسترسی به اینترنت برقرار نیست؛ apt و دانلود وردلیست‌ها بدون آن کار نمی‌کنند."
  fi
}

ensure_tools() {
  local missing=() t
  for t in git wget curl; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if (( ${#missing[@]} == 0 )); then
    ok "ابزارهای پایه موجودند (git، wget، curl)"
    return 0
  fi
  say "نصب ابزارهای جاافتاده: ${missing[*]}"
  if (( DRY_RUN == 1 )); then
    warn "dry-run: apt-get install -y ${missing[*]}"
    return 0
  fi
  apt-get update -qq
  apt-get install -y --no-install-recommends "${missing[@]}" \
    || die "نصب ${missing[*]} ناموفق بود."
  ok "ابزارهای پایه نصب شدند"
}

check_disk() {
  local target=/ avail need_kb=$((3 * 1024 * 1024))
  if [[ -d /opt ]]; then target=/opt; fi
  avail=$(df -Pk "$target" | awk 'NR==2 {print $4}')
  if [[ -z "${avail:-}" ]]; then
    warn "اندازه‌ی فضای دیسک خوانده نشد؛ بررسی فضای آزاد را رد کردم."
  elif (( avail < need_kb )); then
    warn "فضای آزاد $target فقط $((avail / 1024)) مگابایت است؛ وردلیست‌ها حدود ۳ گیگابایت لازم دارند."
    warn "با --quick اجرا کن یا فضا آزاد کن."
  else
    ok "فضای دیسک کافی است ($((avail / 1024 / 1024)) گیگابایت آزاد روی $target)"
  fi
}

check_wifi() {
  local n=0 d
  shopt -s nullglob
  for d in /sys/class/net/*; do
    if [[ -d "$d/wireless" || -d "$d/phy80211" ]]; then n=$((n + 1)); fi
  done
  shopt -u nullglob
  if (( n == 0 )); then
    warn "هیچ اینترفیس وای‌فای پیدا نشد؛ نصب ادامه می‌یابد ولی اجرای autopwn-ng به دانگل نیاز دارد."
  elif (( n == 1 )); then
    warn "فقط یک اینترفیس وای‌فای هست؛ فاز evil twin با یک دانگل خودکار اجرا نمی‌شود."
  else
    ok "$n اینترفیس وای‌فای پیدا شد"
  fi
}

# ---------------------------------------------------------------- steps
run_step() {
  local script="$1" title="$2"
  local path="$REPO_DIR/$script"
  [[ -f "$path" ]] || die "اسکریپت پیدا نشد: $path"
  say "── $title ──"
  if (( DRY_RUN == 1 )); then
    warn "dry-run: bash $script"
    return 0
  fi
  local t0=$SECONDS
  bash "$path" || die "مرحله شکست خورد: $script — خروجی بالا و $LOG_FILE را ببین."
  ok "$title تمام شد ($((SECONDS - t0)) ثانیه)"
}

verify_install() {
  local bin=/usr/local/bin/autopwn-ng t
  if (( DRY_RUN == 1 )); then
    warn "dry-run: بررسی $bin و ابزارهای همراهش"
    return 0
  fi
  [[ -x "$bin" ]] || die "نصب نهایی تأیید نشد: $bin وجود ندارد یا اجراپذیر نیست."
  ok "autopwn-ng نصب شد: $bin"
  for t in hashcat hcxdumptool hcxpcapngtool airodump-ng reaver mdk4 bettercap hostapd-mana bully wash kismet tshark nmap cowpatty; do
    if command -v "$t" >/dev/null 2>&1; then
      ok "  $t"
    else
      warn "  $t پیدا نشد"
    fi
  done
}

# ---------------------------------------------------------------- main
if (( DRY_RUN == 1 )); then
  say "wifite4 — بررسی پیش‌نیازها و نمایش مراحل (dry-run) در $REPO_DIR"
else
  say "wifite4 — نصب خودکار در $REPO_DIR"
fi
say "بررسی پیش‌نیازها…"

check_os
check_network
ensure_tools
check_disk
check_wifi

run_step "install/01-install-packages.sh"  "نصب بسته‌های پایه"
run_step "install/02-build-hostapd-mana.sh" "ساخت و نصب hostapd-mana"

if (( WITH_WORDLISTS == 1 )); then
  run_step "install/03-download-wordlists.sh" "دانلود وردلیست‌ها و ساخت kwp"
else
  warn "مرحله‌ی وردلیست‌ها رد شد (--quick)."
fi

run_step "install-autopwn-ng.sh" "نصب autopwn-ng در /usr/local/bin"
verify_install

ELAPSED=$((SECONDS - START_TS))
if (( DRY_RUN == 1 )); then
  ok "dry-run تمام شد ($((ELAPSED / 60)) دقیقه و $((ELAPSED % 60)) ثانیه) — هیچ تغییری روی سیستم اعمال نشد."
else
  ok "نصب کامل شد در $((ELAPSED / 60)) دقیقه و $((ELAPSED % 60)) ثانیه."
  say "شروع کن با: sudo autopwn-ng --help"
fi
