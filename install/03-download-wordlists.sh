#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v bash >/dev/null 2>&1 || die "bash پیدا نشد."
command -v git  >/dev/null 2>&1 || die "git پیدا نشد: sudo apt-get install -y git"
command -v wget >/dev/null || die "wget پیدا نشد: sudo apt-get install -y wget"
command -v make >/dev/null || die "make پیدا نشد: sudo apt-get install -y make"
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/03-download-wordlists.sh"

# ---------------------------------------------------------------- download
WORDLIST_DIR=/opt/wordlists
mkdir -p "$WORDLIST_DIR"

# rockyou
[ -f "$WORDLIST_DIR/rockyou.txt" ] || \
  wget -q -O "$WORDLIST_DIR/rockyou.txt" \
    https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt

# SecLists (پسوردهای پیش‌فرض روترها)
clone_or_replace "$WORDLIST_DIR/SecLists" \
  https://github.com/danielmiessler/SecLists

# Probable-Wordlists
clone_or_replace "$WORDLIST_DIR/Probable-Wordlists" \
  https://github.com/berzerk0/Probable-Wordlists

# rule های تهاجمی
clone_or_replace "$WORDLIST_DIR/password_cracking_rules" \
  https://github.com/NotSoSecure/password_cracking_rules
mkdir -p /usr/share/hashcat/rules
install -m 644 \
  "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" \
  /usr/share/hashcat/rules/

# keyboard walk
clone_or_replace "$WORDLIST_DIR/kwprocessor" \
  https://github.com/hashcat/kwprocessor
make -C "$WORDLIST_DIR/kwprocessor" -j"$(nproc)"
install -m 755 "$WORDLIST_DIR/kwprocessor/kwp" /usr/local/bin/kwp
install -m 644 \
  "$WORDLIST_DIR/kwprocessor/keyboard-base.txt" \
  "$WORDLIST_DIR/kwprocessor/keyboard-rules.txt" \
  "$WORDLIST_DIR/"
