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
for t in hcxdumptool airodump-ng hashcat; do printf '#!/usr/bin/env bash\nexit 0\n' > "$ACTIVE_MOCK/$t" && chmod +x "$ACTIVE_MOCK/$t"; done
ACTIVE_SCOPE="$(mktemp)"
printf '11:22:33:44:55:66\n' > "$ACTIVE_SCOPE"
PATH="$ACTIVE_MOCK:/usr/bin:/bin" WIFITE4_TEST_MODE=1 bash "$SCRIPT" --target AA:BB:CC:DD:EE:FF --scope "$ACTIVE_SCOPE" --authorize >"$ACTIVE_MOCK/out.txt" 2>&1
ACTIVE_RC=$?
ACTIVE_OUT=$(cat "$ACTIVE_MOCK/out.txt")
if [ "$ACTIVE_RC" -eq 1 ] && printf '%s\n' "$ACTIVE_OUT" | grep -qF "خارج از scope"; then
  echo "  PASS: active mode rejects out-of-scope target"; PASS=$((PASS + 1))
else
  echo "  FAIL: active scope rejection (rc=$ACTIVE_RC)"; FAIL=$((FAIL + 1))
  echo "    output: $(echo "$ACTIVE_OUT" | head -3)"
fi
rm -rf "$ACTIVE_MOCK" "$ACTIVE_SCOPE"

# --- Summary ---
echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if (( FAIL > 0 )); then
  exit 1
fi
exit 0