#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/common.sh"

command -v git  >/dev/null 2>&1 || die "git پیدا نشد: sudo apt-get install -y git"
command -v wget >/dev/null 2>&1 || die "wget پیدا نشد: sudo apt-get install -y wget"
require_root

use_test_prefix
WORDLIST_DIR="${WIFITE4_PREFIX:-}/opt/wordlists"
RULES_DEST="${WIFITE4_PREFIX:-}/usr/share/hashcat/rules"

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

ok "وردلیست‌ها و ruleها آماده شدند."