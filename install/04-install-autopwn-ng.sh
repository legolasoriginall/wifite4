#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SRC_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

[ -f "$SRC" ] || { echo "[-] فایل پیدا نشد: $SRC" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "[-] با sudo اجرا کن: sudo bash install/04-install-autopwn-ng.sh" >&2; exit 1; }

bash -n "$SRC" || { echo "[-] خطای سینتکس در $SRC" >&2; exit 1; }

install -m 755 "$SRC" "$DEST"
echo "[+] نصب شد: $DEST"
echo "[+] اجرا: sudo autopwn-ng --help"
