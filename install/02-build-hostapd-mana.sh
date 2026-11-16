#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v apt-get >/dev/null || die "apt-get پیدا نشد."
command -v git >/dev/null || die "git پیدا نشد. ابتدا نصب کن: sudo apt-get install -y git"
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/02-build-hostapd-mana.sh"

# ---------------------------------------------------------------- install deps + build
apt-get install -y --no-install-recommends \
  libssl-dev libnl-3-dev libnl-genl-3-dev pkg-config make gcc \
  || die "نصب پیش‌نیازهای کامپایل ناموفق بود."

HOSTAPD_DIR=/opt/hostapd-mana

clone_or_replace "$HOSTAPD_DIR" https://github.com/sensepost/hostapd-mana

make -C "$HOSTAPD_DIR/hostapd" -j"$(nproc)"
install -m 755 "$HOSTAPD_DIR/hostapd/hostapd" /usr/local/bin/hostapd-mana
