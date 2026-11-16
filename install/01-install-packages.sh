#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  aircrack-ng hcxtools hcxdumptool hashcat reaver mdk4 \
  bettercap iw pocl-opencl-icd xxd jq
