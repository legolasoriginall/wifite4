#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------- prerequisite checks
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SRC_DIR/autopwn-ng.sh"
DEST="/usr/local/bin/autopwn-ng"

command -v bash >/dev/null 2>&1 || die "bash پیدا نشد."
command -v install >/dev/null 2>&1 || die "install پیدا نشد."
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/04-install-autopwn-ng.sh"
[[ -f "$SRC" ]] || die "فایل پیدا نشد: $SRC"

bash -n "$SRC" || die "خطای سینتکس در $SRC"

# Remove any existing destination (file, symlink, or stale entry) before installing
rm -f "$DEST"
install -m 755 "$SRC" "$DEST"
chmod +x "$DEST"
echo "[+] نصب شد: $DEST (مجوز اجرا: +x)"
echo "[+] اجرا: sudo autopwn-ng --help"
