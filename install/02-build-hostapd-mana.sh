#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v apt-get >/dev/null 2>&1 || die "apt-get پیدا نشد."
command -v git    >/dev/null 2>&1 || die "git پیدا نشد. ابتدا نصب کن: sudo apt-get install -y git"
require_root

apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
  libssl-dev libnl-3-dev libnl-genl-3-dev pkg-config make gcc \
  || die "نصب پیش‌نیازهای کامپایل ناموفق بود."

if [[ "${WIFITE4_TEST_MODE:-0}" == "1" ]]; then
  WIFITE4_PREFIX="${WIFITE4_PREFIX:-$(mktemp -d)}"
  HOSTAPD_DIR="$WIFITE4_PREFIX/opt/hostapd-mana"
  MANA_DEST="$WIFITE4_PREFIX/usr/local/bin/hostapd-mana"
else
  HOSTAPD_DIR=/opt/hostapd-mana
  MANA_DEST=/usr/local/bin/hostapd-mana
fi

clone_or_replace "$HOSTAPD_DIR" https://github.com/sensepost/hostapd-mana

make -C "$HOSTAPD_DIR/hostapd" -j"$(nproc)"
install -m 755 "$HOSTAPD_DIR/hostapd/hostapd" "$MANA_DEST"
ok "hostapd-mana نصب شد: $MANA_DEST"