#!/usr/bin/env bash
# ==========================================================================
#  Integration tests for autopwn-ng.sh
#  Stubs every external tool so no hardware/root is needed, then exercises
#  argument parsing, profile resolution and phase selection through --dry-run.
#  Usage: bash tests/test-integration.sh
# ==========================================================================
set -uo pipefail

PASS=0
FAIL=0

# Repo root (script lives in tests/)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/autopwn-ng.sh"

# ---------------------------------------------------------------- mock tools
# --dry-run never invokes external tools, so mocks are only a safety net.
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT
for t in airmon-ng hcxdumptool hashcat hcxpcapngtool airodump-ng iw; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_DIR/$t" && chmod +x "$MOCK_DIR/$t"
done
export PATH="$MOCK_DIR:$PATH"
export WIFITE4_CHECKPOINT="$MOCK_DIR/checkpoint"

assert_exit() {
  local desc="$1" expected="$2"; shift 2
  local rc
  "$@" >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq $expected ]]; then
    echo "  PASS: $desc (exit $rc)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $rc)"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" pattern="$2"; shift 2
  local out
  out=$("$@" 2>&1)
  if echo "$out" | grep -qF "$pattern"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found)"
    echo "    output: $(echo "$out" | head -3)"; FAIL=$((FAIL + 1))
  fi
}

echo "=== autopwn-ng.sh integration tests (mocked tools) ==="
echo "Script: $SCRIPT"
echo

# --- Profile resolution ---
echo "-- Profile resolution --"
assert_contains "normal profile capture 120s" "Capture: 120s" bash "$SCRIPT" --dry-run
assert_contains "stealth profile capture 240s" "Capture: 240s" bash "$SCRIPT" -p stealth --dry-run
assert_contains "brute profile capture 420s" "Capture: 420s" bash "$SCRIPT" -p brute --dry-run
assert_contains "normal profile label" "Profile: normal" bash "$SCRIPT" --dry-run
assert_contains "stealth profile label" "Profile: stealth" bash "$SCRIPT" -p stealth --dry-run
assert_contains "brute profile label" "Profile: brute" bash "$SCRIPT" -p brute --dry-run
assert_contains "stealth workload 1" "Workload: 1" bash "$SCRIPT" -p stealth --dry-run
assert_contains "brute workload 3" "Workload: 3" bash "$SCRIPT" -p brute --dry-run

# --- Custom capture time overrides profile default ---
echo
echo "-- Custom capture time --"
assert_contains "-t 300 sets capture" "Capture: 300s" bash "$SCRIPT" -t 300 --dry-run
assert_contains "-t 60 overrides stealth" "Capture: 60s" bash "$SCRIPT" -p stealth -t 60 --dry-run

# --- Target / interface / wordlist / dictdir flags ---
echo
echo "-- Target & interface flags --"
assert_contains "--target sets Target line" "Target: AA:BB:CC:DD:EE:FF" bash "$SCRIPT" --target AA:BB:CC:DD:EE:FF --dry-run
assert_contains "-i sets Interface line" "Interface: wlan1" bash "$SCRIPT" -i wlan1 --dry-run
assert_contains "-w sets Wordlist line" "Wordlist: /tmp/wl.txt" bash "$SCRIPT" -w /tmp/wl.txt --dry-run
assert_exit "-i wlan1 --dry-run exits 0" 0 bash "$SCRIPT" -i wlan1 --dry-run
assert_exit "-I wlan2 --dry-run exits 0" 0 bash "$SCRIPT" -I wlan2 --dry-run
assert_exit "-d /tmp/dicts --dry-run exits 0" 0 bash "$SCRIPT" -d /tmp/dicts --dry-run

# --- Feature toggles ---
echo
echo "-- Feature toggles --"
assert_exit "--no-wps --dry-run exits 0" 0 bash "$SCRIPT" --no-wps --dry-run
assert_exit "--no-twin --dry-run exits 0" 0 bash "$SCRIPT" --no-twin --dry-run
assert_exit "--no-post --dry-run exits 0" 0 bash "$SCRIPT" --no-post --dry-run
assert_exit "all toggles combined exits 0" 0 bash "$SCRIPT" --no-wps --no-twin --no-post --dry-run

# --- Auto / resume modes ---
echo
echo "-- Auto & resume modes --"
assert_contains "--auto sets capture 90s" "Capture: 90s" bash "$SCRIPT" --auto --dry-run
assert_contains "--auto prints auto mode" "Mode: auto" bash "$SCRIPT" --auto --dry-run
assert_contains "--resume (no checkpoint) warns" "checkpoint" bash "$SCRIPT" --resume --dry-run

# --- Combined flags ---
echo
echo "-- Combined flags --"
assert_exit "stealth+target+toggles exits 0" 0 bash "$SCRIPT" -p stealth -t 300 --target AA:BB:CC:DD:EE:FF -i wlan1 -I wlan2 --no-wps --no-twin --dry-run
assert_contains "combined capture 300s" "Capture: 300s" bash "$SCRIPT" -p stealth -t 300 --target AA:BB:CC:DD:EE:FF -i wlan1 -I wlan2 --no-wps --no-twin --dry-run
assert_contains "combined target printed" "Target: AA:BB:CC:DD:EE:FF" bash "$SCRIPT" -p stealth -t 300 --target AA:BB:CC:DD:EE:FF -i wlan1 -I wlan2 --no-wps --no-twin --dry-run
assert_contains "combined interface printed" "Interface: wlan1" bash "$SCRIPT" -p stealth -t 300 --target AA:BB:CC:DD:EE:FF -i wlan1 -I wlan2 --no-wps --no-twin --dry-run

# --- Error handling ---
echo
echo "-- Error handling --"
assert_exit "unknown option exits 1" 1 bash "$SCRIPT" --bogus-flag
assert_exit "--simulate accepted" 0 bash "$SCRIPT" --simulate
assert_contains "unknown option prints error" "ناشناس" bash "$SCRIPT" --bogus-flag
assert_exit "-p with no value fails" 1 bash "$SCRIPT" -p
assert_exit "-t with no value fails" 1 bash "$SCRIPT" -t

# --- Targets table truncation ---
echo
echo "-- Targets table truncation --"
TARGETS_CSV="$(mktemp)"
printf 'BSSID, First time seen, Last time seen, channel, Speed, Privacy, Cipher, Authentication, Power, # beacons, # IV, LAN IP, ID-length, ESSID, Key\n' > "$TARGETS_CSV"
for n in $(seq 1 25); do
  printf 'AA:BB:CC:00:00:%02X, 1, 2, 6, 54, WPA2, CCMP, PSK, -50, 10, 0, 0.0.0.0, 5, Net%02d,\n' "$n" "$n" >> "$TARGETS_CSV"
done
eval "$(sed -n '/^collect_targets(){/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^show_targets(){/,/^}/p' "$SCRIPT")"
_c=''; _ok=''; _warn=''; _err=''; _rst=''; _dim=''; _bold=''
collect_targets "$TARGETS_CSV"
TARGETS_OUT=$(show_targets)
TARGETS_ROWS=$(printf '%s\n' "$TARGETS_OUT" | grep -cE '^  +[0-9]+ +[0-9A-F]{2}:' || true)
if printf '%s\n' "$TARGETS_OUT" | grep -qF '25 networks discovered' \
   && printf '%s\n' "$TARGETS_OUT" | grep -qF 'first 20 (truncated)' \
   && [ "$TARGETS_ROWS" -eq 20 ]; then
  echo "  PASS: table shows the real total and truncates to 20 rows"; PASS=$((PASS + 1))
else
  echo "  FAIL: truncation summary wrong (rows=$TARGETS_ROWS)"; FAIL=$((FAIL + 1))
  echo "    output: $(printf '%s\n' "$TARGETS_OUT" | tail -2 | tr '\n' '|')"
fi
rm -f "$TARGETS_CSV"

# --- Color control ---
echo
echo "-- Color control --"
COLOR_OUT=$(bash "$SCRIPT" --color --dry-run 2>&1)
if printf '%s' "$COLOR_OUT" | grep -q $'\033'; then
  echo "  PASS: --color forces ANSI even when piped"; PASS=$((PASS + 1))
else
  echo "  FAIL: --color produced no ANSI"; FAIL=$((FAIL + 1))
fi
NOCOLOR_OUT=$(bash "$SCRIPT" --no-color --dry-run 2>&1)
if ! printf '%s' "$NOCOLOR_OUT" | grep -q $'\033'; then
  echo "  PASS: --no-color emits no ANSI"; PASS=$((PASS + 1))
else
  echo "  FAIL: --no-color still emitted ANSI"; FAIL=$((FAIL + 1))
fi

# --- Dry-run completion message ---
echo
echo "-- Dry-run completion --"
assert_contains "dry-run completion message" "Simulation complete" bash "$SCRIPT" --dry-run
assert_contains "dry-run mentions handshake quality" "Handshake quality" bash "$SCRIPT" --dry-run

# --- Scope & authorization safety ---
echo
echo "-- Scope & authorization --"
assert_contains "--scope sets Scope line" "Scope: /tmp/scope.txt" bash "$SCRIPT" --scope /tmp/scope.txt --dry-run
assert_contains "--authorize acknowledges authorization" "Authorization: acknowledged" bash "$SCRIPT" --authorize --dry-run
assert_contains "no --authorize prints not acknowledged" "Authorization: NOT acknowledged" bash "$SCRIPT" --dry-run
assert_contains "--allow-all sets Allow-all line" "Allow-all: yes" bash "$SCRIPT" --allow-all --dry-run
assert_exit "--scope missing file exits 1" 1 env WIFITE4_TEST_MODE=1 bash "$SCRIPT" --authorize --scope /no/such/file.txt

# in_scope() rejection logic (extracted from script)
SCOPE_TMP="$(mktemp)"
printf 'AA:BB:CC:DD:EE:FF\nallowed-ssid\n' > "$SCOPE_TMP"
# shellcheck disable=SC2034
SCOPE_FILE="$SCOPE_TMP"
eval "$(sed -n '/^in_scope() {/,/^}/p' "$SCRIPT")"
if in_scope "11:22:33:44:55:66" "" ; then
  echo "  FAIL: in_scope should reject out-of-scope BSSID"; FAIL=$((FAIL + 1))
else
  echo "  PASS: in_scope rejects out-of-scope BSSID"; PASS=$((PASS + 1))
fi
rm -f "$SCOPE_TMP"

# --- Active-mode safety (mocked tools) ---
echo
echo "-- Active-mode authorization & scope --"
# Authorization gate in active (non-dry-run) mode: non-interactive without --authorize -> exit 1
WIFITE4_TEST_MODE=1 bash "$SCRIPT" </dev/null >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  echo "  PASS: active mode without --authorize exits 1"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected exit 1, got $rc"; FAIL=$((FAIL + 1))
fi

# Scope filtering in active mode: out-of-scope target -> exit 1 before capture
ACTIVE_MOCK="$(mktemp -d)"
for t in hcxdumptool airodump-ng; do printf '#!/usr/bin/env bash\ntouch "%s/capture_called"\nexit 0\n' "$ACTIVE_MOCK" > "$ACTIVE_MOCK/$t" && chmod +x "$ACTIVE_MOCK/$t"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$ACTIVE_MOCK/hashcat" && chmod +x "$ACTIVE_MOCK/hashcat"
ACTIVE_SCOPE="$(mktemp)"
printf '11:22:33:44:55:66\n' > "$ACTIVE_SCOPE"
PATH="$ACTIVE_MOCK:/usr/bin:/bin" WIFITE4_TEST_MODE=1 bash "$SCRIPT" --target AA:BB:CC:DD:EE:FF --scope "$ACTIVE_SCOPE" --authorize >"$ACTIVE_MOCK/out.txt" 2>&1
ACTIVE_RC=$?
ACTIVE_OUT=$(cat "$ACTIVE_MOCK/out.txt")
if [ "$ACTIVE_RC" -eq 1 ] && printf '%s\n' "$ACTIVE_OUT" | grep -qF "خارج از scope" && [ ! -e "$ACTIVE_MOCK/capture_called" ]; then
  echo "  PASS: active mode rejects out-of-scope target before capture"; PASS=$((PASS + 1))
else
  echo "  FAIL: active scope rejection or capture leaked (rc=$ACTIVE_RC)"; FAIL=$((FAIL + 1))
  echo "    output: $(echo "$ACTIVE_OUT" | head -3)"
fi
rm -rf "$ACTIVE_MOCK" "$ACTIVE_SCOPE"

# Active-mode --allow-all without scope: passes the scope gate
ACTIVE_MOCK2="$(mktemp -d)"
for t in hcxdumptool airodump-ng hashcat; do printf '#!/usr/bin/env bash\nexit 0\n' > "$ACTIVE_MOCK2/$t" && chmod +x "$ACTIVE_MOCK2/$t"; done
PATH="$ACTIVE_MOCK2:/usr/bin:/bin" WIFITE4_TEST_MODE=1 bash "$SCRIPT" --allow-all --authorize -t 1 >"$ACTIVE_MOCK2/out.txt" 2>&1 || true
ACTIVE_OUT2=$(cat "$ACTIVE_MOCK2/out.txt")
if printf '%s\n' "$ACTIVE_OUT2" | grep -qF "allow-all"; then
  echo "  PASS: active mode --allow-all passes scope gate"; PASS=$((PASS + 1))
else
  echo "  FAIL: --allow-all scope gate"; FAIL=$((FAIL + 1))
  echo "    output: $(echo "$ACTIVE_OUT2" | head -3)"
fi
rm -rf "$ACTIVE_MOCK2"

# --- Offline mode (--from-pcap) ---
echo
echo "-- Offline mode (from-pcap) --"
rm -f "$WIFITE4_CHECKPOINT"
OFFLINE_MOCK="$(mktemp -d)"
cat > "$OFFLINE_MOCK/hcxpcapngtool" <<'MOCK'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -E) shift 2;; --eapmschapv2=*) shift;; *) shift;; esac; done
mkdir -p "$(dirname "$out")"
printf 'dummy hash\n' > "$out"
exit 0
MOCK
cat > "$OFFLINE_MOCK/hcxhashtool" <<'MOCK'
#!/usr/bin/env bash
in=""; out=""
while [ $# -gt 0 ]; do case "$1" in -i) in="$2"; shift 2;; -o) out="$2"; shift 2;; *) shift;; esac; done
[ -n "$out" ] && cp "$in" "$out"
exit 0
MOCK
cat > "$OFFLINE_MOCK/hashcat" <<'MOCK'
#!/usr/bin/env bash
touch "$(dirname "$0")/hc_called"
exit 0
MOCK
for t in aircrack-ng tshark; do printf '#!/usr/bin/env bash\nexit 0\n' > "$OFFLINE_MOCK/$t" && chmod +x "$OFFLINE_MOCK/$t"; done
chmod +x "$OFFLINE_MOCK/hcxpcapngtool" "$OFFLINE_MOCK/hcxhashtool" "$OFFLINE_MOCK/hashcat"
OFFLINE_PCAP="$(mktemp)"
printf 'dummy pcap' > "$OFFLINE_PCAP"
OFFLINE_OUT=$(PATH="$OFFLINE_MOCK:/usr/bin:/bin" bash "$SCRIPT" --from-pcap "$OFFLINE_PCAP" 2>&1)
OFFLINE_RC=$?
if [ "$OFFLINE_RC" -eq 0 ] && printf '%s\n' "$OFFLINE_OUT" | grep -qF "فاز ۳" \
   && printf '%s\n' "$OFFLINE_OUT" | grep -qF "دیکشنری SSID/وندور" \
   && [ -e "$OFFLINE_MOCK/hc_called" ]; then
  echo "  PASS: --from-pcap runs crack engine (hashcat) and exits 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: --from-pcap (rc=$OFFLINE_RC)"; FAIL=$((FAIL + 1))
  echo "    output: $(echo "$OFFLINE_OUT" | head -3)"
fi
rm -rf "$OFFLINE_MOCK" "$OFFLINE_PCAP"
rm -f "$WIFITE4_CHECKPOINT"

# --- hashcat --restore path ---
echo
echo "-- hashcat --restore --"
RESTORE_MOCK="$(mktemp -d)"
cat > "$RESTORE_MOCK/hcxpcapngtool" <<'MOCK'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -E) shift 2;; --eapmschapv2=*) shift;; *) shift;; esac; done
mkdir -p "$(dirname "$out")"
printf 'dummy hash\n' > "$out"
exit 0
MOCK
cat > "$RESTORE_MOCK/hcxhashtool" <<'MOCK'
#!/usr/bin/env bash
in=""; out=""
while [ $# -gt 0 ]; do case "$1" in -i) in="$2"; shift 2;; -o) out="$2"; shift 2;; *) shift;; esac; done
[ -n "$out" ] && cp "$in" "$out"
exit 0
MOCK
cat > "$RESTORE_MOCK/hashcat" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RESTORE_MOCK_CALLS"
exit 0
MOCK
for t in aircrack-ng tshark; do printf '#!/usr/bin/env bash\nexit 0\n' > "$RESTORE_MOCK/$t" && chmod +x "$RESTORE_MOCK/$t"; done
chmod +x "$RESTORE_MOCK/hcxpcapngtool" "$RESTORE_MOCK/hcxhashtool" "$RESTORE_MOCK/hashcat"
RESTORE_PCAP="$(mktemp)"
printf 'dummy pcap' > "$RESTORE_PCAP"
export RESTORE_MOCK_CALLS="$RESTORE_MOCK/calls.txt"
RESTORE_OUT=$(PATH="$RESTORE_MOCK:/usr/bin:/bin" bash "$SCRIPT" --from-pcap "$RESTORE_PCAP" --session myrun --restore 2>&1)
RESTORE_RC=$?
RESTORE_SESS_CALLS=$(grep -cF -- '--session' "$RESTORE_MOCK_CALLS" 2>/dev/null || true)
RESTORE_RESTORE_CALLS=$(grep -cF -- '--restore' "$RESTORE_MOCK_CALLS" 2>/dev/null || true)
RESTORE_LAYER_CALLS=$(grep -cF -- ' -a ' "$RESTORE_MOCK_CALLS" 2>/dev/null || true)
if [ "$RESTORE_RC" -eq 0 ] && [ "$RESTORE_SESS_CALLS" -eq 1 ] \
   && [ "$RESTORE_RESTORE_CALLS" -eq 1 ] && [ "$RESTORE_LAYER_CALLS" -eq 0 ] \
   && grep -qF -- '--session myrun' "$RESTORE_MOCK_CALLS" \
   && printf '%s\n' "$RESTORE_OUT" | grep -qF "بازیابی نشست" \
   && ! printf '%s\n' "$RESTORE_OUT" | grep -qF "دیکشنری SSID/وندور"; then
  echo "  PASS: --restore calls hashcat once for session myrun, skips layers, exits 0"; PASS=$((PASS + 1))
else
  echo "  FAIL: --restore (rc=$RESTORE_RC, session-calls=$RESTORE_SESS_CALLS, restore-calls=$RESTORE_RESTORE_CALLS, layer-calls=$RESTORE_LAYER_CALLS)"; FAIL=$((FAIL + 1))
  echo "    output: $(echo "$RESTORE_OUT" | head -3)"
fi
unset RESTORE_MOCK_CALLS
rm -rf "$RESTORE_MOCK" "$RESTORE_PCAP"
rm -f "$WIFITE4_CHECKPOINT"

# --- resume checkpoint persists hashcat session/workload/profile ---
echo
echo "-- resume checkpoint fields --"
rm -f "$WIFITE4_CHECKPOINT"
eval "$(sed -n '/^save_checkpoint() {/,/^}/p' "$SCRIPT")"
CHECKPOINT="$(mktemp)"
# shellcheck disable=SC2034  # the four vars are consumed by the eval'd save_checkpoint()
WORK="/tmp/ckpt-work"
# shellcheck disable=SC2034
SESSION="run42"
# shellcheck disable=SC2034
WLIMIT=1
# shellcheck disable=SC2034
PROFILE="stealth"
save_checkpoint 3
if grep -qxF 'CKPT_SESSION=run42' "$CHECKPOINT" \
   && grep -qxF 'CKPT_WLIMIT=1' "$CHECKPOINT" \
   && grep -qxF 'CKPT_PROFILE=stealth' "$CHECKPOINT"; then
  echo "  PASS: save_checkpoint stores session/workload/profile"; PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint missing fields: $(tr '\n' '|' < "$CHECKPOINT")"; FAIL=$((FAIL + 1))
fi
rm -f "$CHECKPOINT"

RESUME_WORK="$(mktemp -d)"
printf 'CKPT_WORK=%s\nCKPT_PHASE=3\nCKPT_SESSION=run42\nCKPT_WLIMIT=1\nCKPT_PROFILE=stealth\n' \
  "$RESUME_WORK" > "$WIFITE4_CHECKPOINT"
RESUME_OUT=$(bash "$SCRIPT" --resume --dry-run 2>&1)
if printf '%s\n' "$RESUME_OUT" | grep -qF 'Session: run42' \
   && printf '%s\n' "$RESUME_OUT" | grep -qF 'Workload: 1' \
   && printf '%s\n' "$RESUME_OUT" | grep -qF 'Profile: stealth' \
   && printf '%s\n' "$RESUME_OUT" | grep -qF 'ادامه از فاز 4'; then
  echo "  PASS: --resume restores checkpoint session/workload/profile"; PASS=$((PASS + 1))
else
  echo "  FAIL: resume did not restore checkpoint fields"; FAIL=$((FAIL + 1))
  echo "    output: $(printf '%s\n' "$RESUME_OUT" | grep -E 'Session|Workload|Profile' | tr '\n' '|')"
fi

MISMATCH_OUT=$(bash "$SCRIPT" --resume --session cli-run -p brute --dry-run 2>&1)
if printf '%s\n' "$MISMATCH_OUT" | grep -qF 'نشست checkpoint' \
   && printf '%s\n' "$MISMATCH_OUT" | grep -qF 'Session: run42'; then
  echo "  PASS: --resume prefers the checkpoint session and warns on mismatch"; PASS=$((PASS + 1))
else
  echo "  FAIL: resume session mismatch not handled"; FAIL=$((FAIL + 1))
fi

printf 'CKPT_WORK=%s\nCKPT_PHASE=abc\nCKPT_SESSION=run42\n' "$RESUME_WORK" > "$WIFITE4_CHECKPOINT"
INVALID_OUT=$(bash "$SCRIPT" --resume --dry-run 2>&1)
if printf '%s\n' "$INVALID_OUT" | grep -qF 'معتبر نیست'; then
  echo "  PASS: invalid checkpoint is rejected instead of sourced"; PASS=$((PASS + 1))
else
  echo "  FAIL: invalid checkpoint not rejected"; FAIL=$((FAIL + 1))
fi
# forged checkpoint must never be executed (only parsed)
FORGED_DIR="$(mktemp -d)"
{
  printf 'CKPT_WORK=%s\n' "$RESUME_WORK"
  printf 'CKPT_PHASE=3\n'
  # shellcheck disable=SC2016  # literal $(...) must never execute
  printf 'CKPT_SESSION=$(touch %s/session-pwned)\n' "$FORGED_DIR"
  printf 'CKPT_WLIMIT=1\n'
  printf 'CKPT_PROFILE=stealth\n'
  printf 'touch %s/pwned\n' "$FORGED_DIR"
} > "$FORGED_DIR/checkpoint"
WIFITE4_CHECKPOINT="$FORGED_DIR/checkpoint" bash "$SCRIPT" --resume --dry-run >/dev/null 2>&1
FORGED_RC=$?
if [ "$FORGED_RC" -eq 0 ] && [ ! -e "$FORGED_DIR/pwned" ] && [ ! -e "$FORGED_DIR/session-pwned" ]; then
  echo "  PASS: forged checkpoint content is parsed, not executed"; PASS=$((PASS + 1))
else
  echo "  FAIL: forged checkpoint executed (rc=$FORGED_RC)"; FAIL=$((FAIL + 1))
fi

ln -s "$FORGED_DIR/checkpoint" "$FORGED_DIR/link"
LINK_OUT=$(WIFITE4_CHECKPOINT="$FORGED_DIR/link" bash "$SCRIPT" --resume --dry-run 2>&1)
LINK_RC=$?
if [ "$LINK_RC" -eq 0 ] && printf '%s\n' "$LINK_OUT" | grep -qF 'معتبر نیست' && [ ! -e "$FORGED_DIR/pwned" ]; then
  echo "  PASS: checkpoint symlink is refused, not followed"; PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint symlink handling (rc=$LINK_RC)"; FAIL=$((FAIL + 1))
fi
rm -rf "$FORGED_DIR"
rm -rf "$RESUME_WORK"
rm -f "$WIFITE4_CHECKPOINT"

# --- interactive pick: scope/auth gate before filtered capture ---
echo
echo "-- interactive picker scope/authorization gate --"
PICK_MOCK="$(mktemp -d)"
PICK_CALLS="$PICK_MOCK/hc-calls.log"
cat > "$PICK_MOCK/iw" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  dev) printf ' phy#0\n\tInterface wlan0\n' ;;
  *" info") printf '\ttype monitor\n' ;;
  *) : ;;
esac
exit 0
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$PICK_MOCK/airmon-ng"
cat > "$PICK_MOCK/airodump-ng" <<'MOCK'
#!/usr/bin/env bash
w=""
while [ $# -gt 0 ]; do case "$1" in -w) w="$2"; shift 2;; *) shift;; esac; done
[ -n "$w" ] || exit 0
{
  printf 'BSSID, First time seen, Last time seen, channel, Speed, Privacy, Cipher, Authentication, Power, # beacons, # IV, LAN IP, ID-length, ESSID, Key\n'
  printf 'AA:BB:CC:DD:EE:01, 1, 2, 6, 54, WPA2, CCMP, PSK, -40, 1, 0, 0.0.0.0, 4, InNet,\n'
  printf 'AA:BB:CC:DD:EE:02, 1, 2, 11, 54, WPA2, CCMP, PSK, -60, 1, 0, 0.0.0.0, 4, OutNet,\n'
} > "${w}-01.csv"
exit 0
MOCK
cat > "$PICK_MOCK/hcxdumptool" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PICK_CALLS"
exit 0
MOCK
for t in hashcat aircrack-ng tshark hcxhashtool; do printf '#!/usr/bin/env bash\nexit 0\n' > "$PICK_MOCK/$t"; done
chmod +x "$PICK_MOCK"/*
PICK_SCOPE="$(mktemp)"
printf 'AA:BB:CC:DD:EE:01\n' > "$PICK_SCOPE"
printf '2\n' | PICK_CALLS="$PICK_CALLS" PATH="$PICK_MOCK:/usr/bin:/bin" WIFITE4_TEST_MODE=1 WIFITE4_CHECKPOINT="$PICK_MOCK/ckpt" \
  bash "$SCRIPT" --interactive --authorize --scope "$PICK_SCOPE" -t 1 > "$PICK_MOCK/out1.txt" 2>&1
PICK_RC1=$?
PICK_OUT1=$(cat "$PICK_MOCK/out1.txt")
printf '2\n' | PICK_CALLS="$PICK_CALLS" PATH="$PICK_MOCK:/usr/bin:/bin" WIFITE4_TEST_MODE=1 WIFITE4_CHECKPOINT="$PICK_MOCK/ckpt" \
  bash "$SCRIPT" --interactive --scope "$PICK_SCOPE" -t 1 > "$PICK_MOCK/out2.txt" 2>&1
PICK_RC2=$?
if [ "$PICK_RC1" -eq 1 ] && printf '%s\n' "$PICK_OUT1" | grep -qF 'خارج از scope' \
   && [ ! -e "$PICK_CALLS" ]; then
  echo "  PASS: out-of-scope pick aborts before hcxdumptool"; PASS=$((PASS + 1))
else
  echo "  FAIL: out-of-scope pick (rc=$PICK_RC1, calls=$(tr '\n' '|' < "$PICK_CALLS" 2>/dev/null))"; FAIL=$((FAIL + 1))
fi
if [ "$PICK_RC2" -eq 1 ] && [ ! -e "$PICK_CALLS" ]; then
  echo "  PASS: interactive run without --authorize never captures"; PASS=$((PASS + 1))
else
  echo "  FAIL: authorization gate before capture (rc=$PICK_RC2)"; FAIL=$((FAIL + 1))
fi
rm -rf "$PICK_MOCK" "$PICK_SCOPE"

# --- cleanup must not touch host networking in dry-run/offline ---
echo
echo "-- cleanup leaves host networking alone --"
CLEAN_MOCK="$(mktemp -d)"
CLEAN_LOG="$CLEAN_MOCK/host-calls.log"
for t in systemctl ip airmon-ng; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\nexit 0\n' \
    "$t" "$CLEAN_LOG" > "$CLEAN_MOCK/$t"
  chmod +x "$CLEAN_MOCK/$t"
done
cat > "$CLEAN_MOCK/hcxpcapngtool" <<'MOCK'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -E) shift 2;; --eapmschapv2=*) shift;; *) shift;; esac; done
mkdir -p "$(dirname "$out")"; printf 'dummy hash\n' > "$out"
exit 0
MOCK
cat > "$CLEAN_MOCK/hcxhashtool" <<'MOCK'
#!/usr/bin/env bash
in=""; out=""
while [ $# -gt 0 ]; do case "$1" in -i) in="$2"; shift 2;; -o) out="$2"; shift 2;; *) shift;; esac; done
[ -n "$out" ] && cp "$in" "$out"
exit 0
MOCK
for t in hashcat aircrack-ng tshark; do printf '#!/usr/bin/env bash\nexit 0\n' > "$CLEAN_MOCK/$t"; done
chmod +x "$CLEAN_MOCK/hcxpcapngtool" "$CLEAN_MOCK/hcxhashtool" "$CLEAN_MOCK/hashcat" "$CLEAN_MOCK/aircrack-ng" "$CLEAN_MOCK/tshark"
CLEAN_PCAP="$(mktemp)"
printf 'dummy pcap' > "$CLEAN_PCAP"
PATH="$CLEAN_MOCK:/usr/bin:/bin" bash "$SCRIPT" --dry-run >/dev/null 2>&1
CLEAN_DRY_RC=$?
PATH="$CLEAN_MOCK:/usr/bin:/bin" bash "$SCRIPT" --from-pcap "$CLEAN_PCAP" >/dev/null 2>&1
CLEAN_OFF_RC=$?
CLEAN_CALLS="$(cat "$CLEAN_LOG" 2>/dev/null || true)"
if [ "$CLEAN_DRY_RC" -eq 0 ] && [ "$CLEAN_OFF_RC" -eq 0 ] && [ -z "$CLEAN_CALLS" ]; then
  echo "  PASS: dry-run/offline cleanup calls no systemctl/ip/airmon-ng"; PASS=$((PASS + 1))
else
  echo "  FAIL: cleanup touched host networking (dry=$CLEAN_DRY_RC, offline=$CLEAN_OFF_RC)"
  echo "    calls: $(printf '%s' "$CLEAN_CALLS" | tr '\n' '|')"; FAIL=$((FAIL + 1))
fi
rm -rf "$CLEAN_MOCK" "$CLEAN_PCAP"
rm -f "$WIFITE4_CHECKPOINT"

# --- Summary ---
echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if (( FAIL > 0 )); then
  exit 1
fi
exit 0