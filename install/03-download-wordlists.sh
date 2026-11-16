#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------- prerequisite checks
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git پیدا نشد. ابتدا نصب کن: sudo apt-get install -y git"
command -v wget >/dev/null 2>&1 || die "wget پیدا نشد. ابتدا نصب کن: sudo apt-get install -y wget"
command -v make >/dev/null 2>&1 || die "make پیدا نشد."
(( EUID == 0 )) || die "به root نیاز دارد: sudo bash install/03-download-wordlists.sh"

# ---------------------------------------------------------------- download
WORDLIST_DIR=/opt/wordlists
sudo mkdir -p "$WORDLIST_DIR"

# Clone a repo, or replace it if a previous clone was partial/invalid
clone_or_replace() {
  local dir="$1" url="$2"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --depth 1 "$url" "$dir"
  fi
}

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
if [ ! -f "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" ]; then
  clone_or_replace "$WORDLIST_DIR/password_cracking_rules" \
    https://github.com/NotSoSecure/password_cracking_rules
fi
sudo install -m 644 \
  "$WORDLIST_DIR/password_cracking_rules/OneRuleToRuleThemAll.rule" \
  /usr/share/hashcat/rules/

# keyboard walk
clone_or_replace "$WORDLIST_DIR/kwprocessor" \
  https://github.com/hashcat/kwprocessor
make -C "$WORDLIST_DIR/kwprocessor" -j"$(nproc)"
sudo install -m 755 "$WORDLIST_DIR/kwprocessor/kwp" /usr/local/bin/kwp
sudo install -m 644 \
  "$WORDLIST_DIR/kwprocessor/keyboard-base.txt" \
  "$WORDLIST_DIR/kwprocessor/keyboard-rules.txt" \
  "$WORDLIST_DIR/"
