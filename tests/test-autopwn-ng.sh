#!/usr/bin/env bash
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
assert_output_contains "--dry-run prints simulation header" "SIMULATION MODE" bash "$SCRIPT" --dry-run
assert_output_contains "--simulate prints simulation header" "SIMULATION MODE" bash "$SCRIPT" --simulate
assert_output_contains "--dry-run prints completion message" "Simulation complete" bash "$SCRIPT" --dry-run

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

# --- Summary ---
echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if (( FAIL > 0 )); then
  exit 1
fi
exit 0