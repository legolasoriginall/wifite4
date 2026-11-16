#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- prerequisite checks
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد."
command -v git >/dev/null 2>&1 || die "git پیدا نشد. ابتدا نصب کن: sudo apt-get install -y git"
command -v make >/dev/null 2>&1 || die "make پیدا نشد."
command -v gcc >/dev/null 2>&1 || die "gcc پیدا نشد."
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/02-build-hostapd-mana.sh"

# ---------------------------------------------------------------- install deps + build
sudo apt-get install -y --no-install-recommends \
  libssl-dev libnl-3-dev libnl-genl-3-dev pkg-config make gcc \
  || die "نصب پیش‌نیازهای کامپایل ناموفق بود."

HOSTAPD_DIR=/opt/hostapd-mana

# Skip valid clones; remove and replace partial/invalid ones
if [ ! -d "$HOSTAPD_DIR/.git" ]; then
  rm -rf "$HOSTAPD_DIR"
  git clone --depth 1 https://github.com/sensepost/hostapd-mana "$HOSTAPD_DIR"
fi

make -C "$HOSTAPD_DIR/hostapd" -j"$(nproc)"
sudo install -m 755 "$HOSTAPD_DIR/hostapd/hostapd" /usr/local/bin/hostapd-mana
