#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- prerequisite checks
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد. این اسکریپت فقط روی Debian/Ubuntu/Kali/Parrot کار می‌کند."
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/01-install-packages.sh"
command -v sudo >/dev/null 2>&1 || die "sudo پیدا نشد."

# ---------------------------------------------------------------- install
# apt-get update may fail on transient network issues; warn but continue
sudo apt-get update || echo "[!] apt-get update had issues, continuing..." >&2

# apt-get install is idempotent: already-installed packages are skipped
sudo apt-get install -y --no-install-recommends \
  aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 \
  bettercap iw pocl-opencl-icd xxd jq \
  || die "نصب بسته‌ها ناموفق بود. خروجی apt-get را بررسی کن."

echo "[+] بسته‌های پایه نصب/به‌روز شدند."
