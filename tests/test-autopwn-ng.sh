#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2317,SC2329  # helpers/vars below are used by eval'd code
# ==========================================================================
#  Lightweight unit tests for autopwn-ng.sh
#  Runs without root or hardware — uses --dry-run/--simulate/--help only.
#  Usage: bash tests/test-autopwn-ng.sh
# ==========================================================================
set -uo pipefail
PASS=0
FAIL=0
SCRIPT="${1:-autopwn-ng.sh}"

# Resolve script path relative to repo root
if [[ ! -f "$SCRIPT" ]]; then
  # try from repo root
  SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/autopwn-ng.sh"
fi

assert_exit() {
  local desc="$1" expected="$2"; shift 2
  "$@" >/dev/null 2>&1
  local rc=$?
  if [[ $rc -eq $expected ]]; then
    echo "  PASS: $desc (exit $rc)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $rc)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local desc="$1" pattern="$2"; shift 2
  local out
  out=$("$@" 2>&1)
  if echo "$out" | grep -qF "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found)"
    echo "    output: $(echo "$out" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== autopwn-ng.sh unit tests ==="
echo "Script: $SCRIPT"
echo

# --- Help ---
echo "-- Help --"
assert_exit "--help exits 0" 0 bash "$SCRIPT" --help
assert_exit "-h exits 0" 0 bash "$SCRIPT" -h
assert_output_contains "--help prints usage" "autopwn-ng" bash "$SCRIPT" --help

# --- Dry-run / simulate ---
echo
echo "-- Dry-run & simulate --"
assert_exit "--dry-run exits 0" 0 bash "$SCRIPT" --dry-run
assert_exit "--simulate exits 0" 0 bash "$SCRIPT" --simulate
assert_output_contains "dry-run mentions handshake quality" "Handshake quality" bash "$SCRIPT" --dry-run
assert_output_contains "--dry-run prints simulation header" "SIMULATION MODE" bash "$SCRIPT" --dry-run
assert_output_contains "--simulate prints simulation header" "SIMULATION MODE" bash "$SCRIPT" --simulate
assert_output_contains "--dry-run prints completion message" "Simulation complete" bash "$SCRIPT" --dry-run

# --- Known WPS PIN computation ---
echo
echo "-- Known WPS PIN computation --"
assert_exit "--compute-wps-pins exits 0" 0 bash "$SCRIPT" --compute-wps-pins C8:3A:35:00:B0:0C
assert_output_contains "--compute-wps-pins emits 8-digit PIN" "12345670" bash "$SCRIPT" --compute-wps-pins C8:3A:35:00:B0:0C
assert_output_contains "--compute-wps-pins emits default PIN" "00000000" bash "$SCRIPT" --compute-wps-pins C8:3A:35:00:B0:0C
assert_output_contains "--compute-wps-pins uses bundled DB" "98765432" bash "$SCRIPT" --compute-wps-pins 00:11:22:33:44:55
assert_exit "--wep --dry-run exits 0" 0 bash "$SCRIPT" --wep --dry-run
assert_output_contains "--wep --dry-run prints WEP mode" "WEP cracking" bash "$SCRIPT" --wep --dry-run
assert_exit "--wps-state --dry-run exits 0" 0 bash "$SCRIPT" --wps-state /tmp/wps.tsv --dry-run
assert_output_contains "--dry-run prints WPS priority" "WPS: NULL PIN" bash "$SCRIPT" --dry-run
assert_exit "--no-config-extract --dry-run exits 0" 0 bash "$SCRIPT" --no-config-extract --dry-run
assert_output_contains "--dry-run prints config extract" "Config extract: enabled" bash "$SCRIPT" --dry-run
assert_exit "--no-default-psk --dry-run exits 0" 0 bash "$SCRIPT" --no-default-psk --dry-run
assert_output_contains "--dry-run prints default psk" "Default PSK: enabled" bash "$SCRIPT" --dry-run

# --- Profile selection via dry-run output ---
echo
echo "-- Profile selection --"
assert_output_contains "normal profile capture 120s" "Capture: 120s" bash "$SCRIPT" --dry-run
assert_output_contains "stealth profile capture 240s" "Capture: 240s" bash "$SCRIPT" -p stealth --dry-run
assert_output_contains "brute profile capture 420s" "Capture: 420s" bash "$SCRIPT" -p brute --dry-run

# --- Custom capture time ---
echo
echo "-- Custom capture time --"
assert_output_contains "-t 300 sets capture 300s" "Capture: 300s" bash "$SCRIPT" -t 300 --dry-run
assert_output_contains "stealth without -t defaults to 240s" "Capture: 240s" bash "$SCRIPT" -p stealth --dry-run
assert_output_contains "-t 60 overrides stealth capture" "Capture: 60s" bash "$SCRIPT" -p stealth -t 60 --dry-run

# --- Auto mode ---
echo
echo "-- Auto mode --"
assert_exit "--auto --dry-run exits 0" 0 bash "$SCRIPT" --auto --dry-run
assert_output_contains "--auto sets capture 90s" "Capture: 90s" bash "$SCRIPT" --auto --dry-run
assert_output_contains "--auto prints auto mode" "Mode: auto" bash "$SCRIPT" --auto --dry-run

# --- Resume mode ---
echo
echo "-- Resume mode --"
assert_exit "--resume --dry-run exits 0" 0 bash "$SCRIPT" --resume --dry-run
assert_output_contains "--resume (no checkpoint) prints warning" "checkpoint" bash "$SCRIPT" --resume --dry-run
assert_output_contains "--resume --dry-run prints simulation header" "SIMULATION MODE" bash "$SCRIPT" --resume --dry-run

# --- Unknown option ---
echo
echo "-- Error handling --"
assert_exit "unknown option exits 1" 1 bash "$SCRIPT" --bogus-flag

# --- Combined flags ---
echo
echo "-- Combined flags --"
assert_exit "-p stealth -t 300 --dry-run exits 0" 0 bash "$SCRIPT" -p stealth -t 300 --dry-run
assert_output_contains "combined flags capture 300s" "Capture: 300s" bash "$SCRIPT" -p stealth -t 300 --dry-run

# --- Flag parsing (no-hardware) ---
echo
echo "-- Flag parsing --"
assert_exit "--no-wps --dry-run exits 0" 0 bash "$SCRIPT" --no-wps --dry-run
assert_exit "--no-twin --dry-run exits 0" 0 bash "$SCRIPT" --no-twin --dry-run
assert_exit "--no-post --dry-run exits 0" 0 bash "$SCRIPT" --no-post --dry-run
assert_exit "--no-harvest --dry-run exits 0" 0 bash "$SCRIPT" --no-harvest --dry-run
assert_exit "--harvest-time 10 --dry-run exits 0" 0 bash "$SCRIPT" --harvest-time 10 --dry-run
assert_exit "--target BSSID --dry-run exits 0" 0 bash "$SCRIPT" --target aa:bb:cc:dd:ee:ff --dry-run
assert_exit "-i iface --dry-run exits 0" 0 bash "$SCRIPT" -i wlan0 --dry-run
assert_exit "-w wordlist --dry-run exits 0" 0 bash "$SCRIPT" -w /tmp/wl.txt --dry-run
assert_exit "-d dictdir --dry-run exits 0" 0 bash "$SCRIPT" -d /tmp/dicts --dry-run
assert_output_contains "--target prints target" "Target: aa:bb:cc:dd:ee:ff" bash "$SCRIPT" --target aa:bb:cc:dd:ee:ff --dry-run
assert_output_contains "--resume without checkpoint warns" "checkpoint" bash "$SCRIPT" --resume --dry-run

# --- Profile selection (all profiles) ---
echo
echo "-- All profiles --"
assert_exit "stealth profile exits 0" 0 bash "$SCRIPT" -p stealth --dry-run
assert_exit "brute profile exits 0" 0 bash "$SCRIPT" -p brute --dry-run
assert_exit "normal profile exits 0" 0 bash "$SCRIPT" -p normal --dry-run
assert_exit "unknown profile still exits 0" 0 bash "$SCRIPT" -p bogus --dry-run

# --- parse_pcap_creds (mocked tshark) ---
echo
echo "-- parse_pcap_creds --"
MOCKBIN="$(mktemp -d)"
trap 'rm -rf "$MOCKBIN"' EXIT
cat > "$MOCKBIN/tshark" <<'MOCK'
#!/usr/bin/env bash
args="$*"
if echo "$args" | grep -q 'Basic'; then
  printf 't1\t10.0.0.1\texample.com\tGET\t/login\tBasic YWRtaW46c2VjcmV0\n'
elif echo "$args" | grep -q 'POST'; then
  printf 't2\t10.0.0.2\texample.com\t/login\tusername=alice&password=p4ss\n'
fi
exit 0
MOCK
chmod +x "$MOCKBIN/tshark"
PCAP="$MOCKBIN/sample.pcap"
printf 'dummy' > "$PCAP"
LOOT_OUT=$(PATH="$MOCKBIN:$PATH" bash "$SCRIPT" --parse-pcap "$PCAP" 2>&1)
if echo "$LOOT_OUT" | grep -qF "admin" && echo "$LOOT_OUT" | grep -qF "alice"; then
  echo "  PASS: parse_pcap_creds populates loot.tsv (Basic + Form)"; PASS=$((PASS + 1))
else
  echo "  FAIL: parse_pcap_creds (expected admin and alice)"
  echo "    output: $(echo "$LOOT_OUT" | head -5)"; FAIL=$((FAIL + 1))
fi
if echo "$LOOT_OUT" | grep -qF "Basic" && echo "$LOOT_OUT" | grep -qF "Form"; then
  echo "  PASS: parse_pcap_creds types present"; PASS=$((PASS + 1))
else
  echo "  FAIL: parse_pcap_creds (expected Basic and Form types)"
  echo "    output: $(echo "$LOOT_OUT" | head -5)"; FAIL=$((FAIL + 1))
fi

# --- Scope & authorization safety ---
echo
echo "-- Scope & authorization --"
assert_output_contains "--scope sets Scope line" "Scope: /tmp/scope.txt" bash "$SCRIPT" --scope /tmp/scope.txt --dry-run
assert_output_contains "--authorize acknowledges authorization" "Authorization: acknowledged" bash "$SCRIPT" --authorize --dry-run
assert_output_contains "no --authorize prints not acknowledged" "Authorization: NOT acknowledged" bash "$SCRIPT" --dry-run
assert_output_contains "--allow-all sets Allow-all line" "Allow-all: yes" bash "$SCRIPT" --allow-all --dry-run

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
if in_scope "AA:BB:CC:DD:EE:FF" "" ; then
  echo "  PASS: in_scope accepts in-scope BSSID"; PASS=$((PASS + 1))
else
  echo "  FAIL: in_scope should accept in-scope BSSID"; FAIL=$((FAIL + 1))
fi
if in_scope "00:00:00:00:00:00" "allowed-ssid" ; then
  echo "  PASS: in_scope accepts in-scope SSID"; PASS=$((PASS + 1))
else
  echo "  FAIL: in_scope should accept in-scope SSID"; FAIL=$((FAIL + 1))
fi
rm -f "$SCOPE_TMP"

# select_target() menu logic (extracted)
eval "$(sed -n '/^in_scope() {/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^select_target(){/,/^}/p' "$SCRIPT")"
warn(){ :; }; err(){ :; }; ok(){ :; }
_ok=''; _rst=''
INTERACTIVE=1
TARGET=''; TARGET_ESSID=''; SCOPE_FILE=''
TARGET_ROWS=$'AA:BB:CC:DD:EE:01|6|-40|WPA2|Home\nAA:BB:CC:DD:EE:02|11|-70|WPA2|Cafe'
select_target <<< '2' >/dev/null
if [ "$TARGET" = 'AA:BB:CC:DD:EE:02' ] && [ "$TARGET_ESSID" = 'Cafe' ]; then
  echo "  PASS: select_target picks the numbered row"; PASS=$((PASS + 1))
else
  echo "  FAIL: select_target picked '$TARGET' / '$TARGET_ESSID'"; FAIL=$((FAIL + 1))
fi
TARGET=''; TARGET_ESSID=''
select_target <<< '99' >/dev/null
if [ -z "$TARGET" ]; then
  echo "  PASS: select_target ignores an out-of-range number"; PASS=$((PASS + 1))
else
  echo "  FAIL: out-of-range number selected '$TARGET'"; FAIL=$((FAIL + 1))
fi
SELECT_SCOPE="$(mktemp)"
printf 'AA:BB:CC:DD:EE:01\n' > "$SELECT_SCOPE"
SCOPE_FILE="$SELECT_SCOPE"
TARGET=''; TARGET_ESSID=''
select_target <<< '2' >/dev/null; sel_rc=$?
if [ "$sel_rc" -eq 1 ] && [ -z "$TARGET" ]; then
  echo "  PASS: select_target rejects an out-of-scope pick"; PASS=$((PASS + 1))
else
  echo "  FAIL: out-of-scope pick (rc=$sel_rc, target='$TARGET')"; FAIL=$((FAIL + 1))
fi
rm -f "$SELECT_SCOPE"
SCOPE_FILE=''

# Authorization rejection path (non-interactive, no --authorize)
WIFITE4_TEST_MODE=1 bash "$SCRIPT" </dev/null >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  echo "  PASS: non-interactive run without --authorize exits 1"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected exit 1, got $rc"; FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if (( FAIL > 0 )); then
  exit 1
fi
exit 0