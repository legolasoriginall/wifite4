#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد. این اسکریپت فقط روی Debian/Ubuntu/Kali/Parrot کار می‌کند."
require_root

apt-get -o APT::Sandbox::User=root update || warn "apt-get update had issues, continuing..."

apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
  aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 \
  bettercap iw xxd jq \
  bully tshark dnsmasq nmap \
  || die "نصب بسته‌ها ناموفق بود. خروجی apt-get را بررسی کن."

command -v wash >/dev/null 2>&1 || warn "wash یافت نشد (با بستهٔ reaver نصب می‌شود)."
command -v kismet >/dev/null 2>&1 || warn "kismet در مخازن پیش‌فرض موجود نیست."

ok "بسته‌های پایه نصب/به‌روز شدند."