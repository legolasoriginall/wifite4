#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get install -y --no-install-recommends \
  libssl-dev libnl-3-dev libnl-genl-3-dev pkg-config make gcc

HOSTAPD_DIR=/opt/hostapd-mana
[ -d "$HOSTAPD_DIR" ] || git clone --depth 1 https://github.com/sensepost/hostapd-mana "$HOSTAPD_DIR"

make -C "$HOSTAPD_DIR/hostapd" -j"$(nproc)"
sudo install -m 755 "$HOSTAPD_DIR/hostapd/hostapd" /usr/local/bin/hostapd-mana
