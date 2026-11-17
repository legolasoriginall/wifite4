#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v git  >/dev/null 2>&1 || die "git پیدا نشد: sudo apt-get install -y git"
command -v wget >/dev/null 2>&1 || die "wget پیدا نشد: sudo apt-get install -y wget"
command -v make >/dev/null 2>&1 || die "make پیدا نشد: sudo apt-get install -y make"
require_root

if [[ "${WIFITE4_TEST_MODE:-0}" == "1" ]]; then
  WIFITE4_PREFIX="${WIFITE4_PREFIX:-$(mktemp -d)}"
  WORDLIST_DIR="$WIFITE4_PREFIX/opt/wordlists"
  RULES_DEST="$WIFITE4_PREFIX/usr/share/hashcat/rules"
  KWP_DEST="$WIFITE4_PREFIX/usr/local/bin/kwp"
  KB_DEST="$WIFITE4_PREFIX/opt/wordlists"
else
  WORDLIST_DIR=/opt/wordlists
  RULES_DEST=/usr/share/hashcat/rules
  KWP_DEST=/usr/local/bin/kwp
  KB_DEST=/opt/wordlists
fi

mkdir -p "$WORDLIST_DIR" "$RULES_DEST"

[ -f "$WORDLIST_DIR/rockyou.txt" ] || \
  wget -q -O "$WORDLIST_DIR/rockyou.txt" \
    https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt

clone_or_replace "$WORDLIST_DIR/SecLists" \
  https://github.com/danielmiessler/SecLists

clone_or_replace "$WORDLIST_DIR/Probable-Wordlists" \
  https://github.com/berzerk0/Probable-Wordlists

clone_or_replace "$WORDLIST_DIR/password_cracking_rules" \
  https://github.com/NotSoSecure/password_cracking_rules
install -m 644 \
  "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" \
  "$RULES_DEST/"

clone_or_replace "$WORDLIST_DIR/kwprocessor" \
  https://github.com/hashcat/kwprocessor
make -C "$WORDLIST_DIR/kwprocessor" -j"$(nproc)"
install -m 755 "$WORDLIST_DIR/kwprocessor/kwp" "$KWP_DEST"
install -m 644 \
  "$WORDLIST_DIR/kwprocessor/keyboard-base.txt" \
  "$WORDLIST_DIR/kwprocessor/keyboard-rules.txt" \
  "$KB_DEST/"

ok "وردلیست‌ها و ابزارها آماده شدند."