#!/usr/bin/env bash
set -euo pipefail

WORDLIST_DIR=/opt/wordlists
sudo mkdir -p "$WORDLIST_DIR"

# rockyou
[ -f "$WORDLIST_DIR/rockyou.txt" ] || \
  wget -q -O "$WORDLIST_DIR/rockyou.txt" \
    https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt

# SecLists (پسوردهای پیش‌فرض روترها)
[ -d "$WORDLIST_DIR/SecLists" ] || \
  git clone --depth 1 https://github.com/danielmiessler/SecLists "$WORDLIST_DIR/SecLists"

# Probable-Wordlists
[ -d "$WORDLIST_DIR/Probable-Wordlists" ] || \
  git clone --depth 1 https://github.com/berzerk0/Probable-Wordlists "$WORDLIST_DIR/Probable-Wordlists"

# rule های تهاجمی
if [ ! -f "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" ]; then
  git clone --depth 1 https://github.com/NotSoSecure/password_cracking_rules \
    "$WORDLIST_DIR/password_cracking_rules"
fi
sudo install -m 644 \
  "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" \
  /usr/share/hashcat/rules/

# keyboard walk
[ -d "$WORDLIST_DIR/kwprocessor" ] || \
  git clone https://github.com/hashcat/kwprocessor "$WORDLIST_DIR/kwprocessor"
make -C "$WORDLIST_DIR/kwprocessor" -j"$(nproc)"
sudo install -m 755 "$WORDLIST_DIR/kwprocessor/kwp" /usr/local/bin/kwp
sudo install -m 644 \
  "$WORDLIST_DIR/kwprocessor/keyboard-base.txt" \
  "$WORDLIST_DIR/kwprocessor/keyboard-rules.txt" \
  "$WORDLIST_DIR/"
