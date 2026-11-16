#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد. این اسکریپت فقط روی Debian/Ubuntu/Kali/Parrot کار می‌کند."
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/01-install-packages.sh"

# ---------------------------------------------------------------- install
# apt-get update may fail on transient network issues; warn but continue
apt-get update || echo "[!] apt-get update had issues, continuing..." >&2

# apt-get install is idempotent: already-installed packages are skipped
apt-get install -y --no-install-recommends \
  aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 \
  bettercap iw xxd jq \
  bully wash kismet tshark dnsmasq nmap cowpatty \
  || die "نصب بسته‌ها ناموفق بود. خروجی apt-get را بررسی کن."

echo "[+] بسته‌های پایه نصب/به‌روز شدند."
