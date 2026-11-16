#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y aircrack-ng hcxtools hcxdumptool hashcat reaver bully mdk4 \
  kismet bettercap iw pocl-opencl-icd xxd jq
