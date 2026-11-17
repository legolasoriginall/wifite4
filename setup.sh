#!/usr/bin/env bash
# ==========================================================================
#  wifite4 — نصب کامل و خودکار
#  استفاده: sudo bash setup.sh [--quick] [--only-autopwn] [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${WIFITE4_PREFIX:-}/var/log/wifite4-setup.log"
DOWNLOAD_WORDLISTS=1
DRY_RUN=0
ONLY_AUTOPWN=0

# shellcheck disable=SC1091
. "$(dirname "$0")/install/common.sh"

usage() {
  cat <<'EOF'
نصب خودکار و ترتیبی همه‌ی مراحل wifite4.

استفاده:
  sudo bash setup.sh                 نصب کامل (پیش‌فرض: شامل وردلیست‌ها)
  sudo bash setup.sh --quick         نصب سریع، بدون دانلود وردلیست‌ها
  sudo bash setup.sh --only-autopwn  فقط نصب مجدد autopwn-ng (بدون بسته‌ها/وردلیست)
  bash setup.sh --dry-run            فقط بررسی پیش‌نیازها و نمایش مراحل
  bash setup.sh --help               همین راهنما

گزینه‌ها:
  --quick          بدون دانلود وردلیست‌ها (سریع‌تر)
  --dry-run        فقط بررسی پیش‌نیازها و نمایش مراحل
  --only-autopwn   فقط نصب مجدد autopwn-ng در /usr/local/bin
  --help           همین راهنما

مراحل:
  1) install/01-install-packages.sh      بسته‌های پایه
  2) install/02-build-hostapd-mana.sh    ساخت و نصب hostapd-mana
  3) install/03-download-wordlists.sh    دانلود وردلیست‌ها، ruleها و ساخت kwp (با --quick رد می‌شود)
  4) install-autopwn-ng.sh    نصب autopwn-ng در /usr/local/bin

گزارش اجرا در /var/log/wifite4-setup.log ذخیره می‌شود.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --quick)        DOWNLOAD_WORDLISTS=0 ;;
    --full)         ;;  # backward-compatible no-op (full install is default)
    --dry-run)      DRY_RUN=1 ;;
    --only-autopwn) ONLY_AUTOPWN=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; die "گزینه‌ی ناشناخته: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- root
ensure_root "$@"

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
  apt-get -o APT::Sandbox::User=root update -qq
  apt-get -o APT::Sandbox::User=root install -y --no-install-recommends "${missing[@]}" \
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
  local bin="${WIFITE4_PREFIX:-}/usr/local/bin/autopwn-ng" t
  if (( DRY_RUN == 1 )); then
    warn "dry-run: بررسی $bin و ابزارهای همراهش"
    return 0
  fi
  [[ -x "$bin" ]] || die "نصب نهایی تأیید نشد: $bin وجود ندارد یا اجراپذیر نیست."
  ok "autopwn-ng نصب شد: $bin"
  for t in hashcat hcxdumptool hcxpcapngtool airodump-ng reaver mdk4 bettercap hostapd-mana bully wash kismet tshark nmap; do
    if command -v "$t" >/dev/null 2>&1; then
      ok "  $t"
    else
      warn "  $t پیدا نشد"
    fi
  done
}

# ---------------------------------------------------------------- main
if (( ONLY_AUTOPWN == 1 )); then
  say "wifite4 — فقط نصب مجدد autopwn-ng در $REPO_DIR"
elif (( DRY_RUN == 1 )); then
  say "wifite4 — بررسی پیش‌نیازها و نمایش مراحل (dry-run) در $REPO_DIR"
else
  say "wifite4 — نصب خودکار در $REPO_DIR"
fi
if (( ONLY_AUTOPWN == 1 )); then
  run_step "install-autopwn-ng.sh" "نصب autopwn-ng در /usr/local/bin"
  verify_install
else
  say "بررسی پیش‌نیازها…"
  check_os
  check_network
  ensure_tools
  check_disk
  check_wifi

  run_step "install/01-install-packages.sh"  "نصب بسته‌های پایه"
  run_step "install/02-build-hostapd-mana.sh" "ساخت و نصب hostapd-mana"

  if (( DOWNLOAD_WORDLISTS == 1 )); then
    run_step "install/03-download-wordlists.sh" "دانلود وردلیست‌ها و ساخت kwp"
  else
    warn "مرحله‌ی وردلیست‌ها رد شد (--quick)."
  fi

  run_step "install-autopwn-ng.sh" "نصب autopwn-ng در /usr/local/bin"
  verify_install
fi

ELAPSED=$((SECONDS - START_TS))
if (( DRY_RUN == 1 )); then
  ok "dry-run تمام شد ($((ELAPSED / 60)) دقیقه و $((ELAPSED % 60)) ثانیه) — هیچ تغییری روی سیستم اعمال نشد."
else
  ok "نصب کامل شد در $((ELAPSED / 60)) دقیقه و $((ELAPSED % 60)) ثانیه."
  say "شروع کن با: sudo autopwn-ng --help"
fi
