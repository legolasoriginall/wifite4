#!/usr/bin/env bash
# ==========================================================================
#  نصب autopwn-ng در مسیر سیستم با مجوز اجرا
#  استفاده: sudo bash install-autopwn-ng.sh [--dry-run] [--help]
# ==========================================================================
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo "Usage: sudo bash install-autopwn-ng.sh [--dry-run]"; exit 0 ;;
    *)         echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if (( EUID != 0 && DRY_RUN == 0 )); then
  echo "Root required: sudo bash install-autopwn-ng.sh" >&2
  exit 1
fi
[[ -f "$SRC" ]] || { echo "File not found: $SRC" >&2; exit 1; }
bash -n "$SRC" || { echo "Syntax error in $SRC" >&2; exit 1; }

if (( DRY_RUN == 1 )); then
  echo "dry-run: install -m 755 $SRC $DEST"
  exit 0
fi

install -m 755 "$SRC" "$DEST"
echo "Installed: $DEST"
echo "Run: sudo autopwn-ng --help"