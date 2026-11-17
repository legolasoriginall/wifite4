#!/usr/bin/env bash
# ==========================================================================
#  Mock test: simulate partial install failure, verify safe rerun
#  Usage: bash tests/test-rerun.sh
# ==========================================================================
set -uo pipefail
# shellcheck disable=SC2034,SC2317,SC2329

# Test mode: allow install scripts to run without root in restricted CI environments
export WIFITE4_TEST_MODE=1
WIFITE4_PREFIX="$(mktemp -d)"
export WIFITE4_PREFIX

PASS=0
FAIL=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOCK_DIR="$(mktemp -d)"
# Prepend mock dir so mocks override, but keep system tools available
export PATH="$MOCK_DIR:$PATH"

# shellcheck disable=SC2317,SC2329
cleanup() {
  rm -rf "$MOCK_DIR"
  rm -rf "$WIFITE4_PREFIX"
}
trap cleanup EXIT

# ---------- mock tools ----------
# apt-get: succeed normally
cat > "$MOCK_DIR/apt-get" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$MOCK_DIR/apt-get"

# git: clone creates .git marker; track call count for partial-failure sim
cat > "$MOCK_DIR/git" <<'SH'
#!/usr/bin/env bash
MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_CALLS="$MOCK_DIR/git_calls"
[[ -f "$GIT_CALLS" ]] || echo 0 > "$GIT_CALLS"
if [[ "$1" == "clone" ]]; then
  dir="${@: -1}"
  calls=$(cat "$GIT_CALLS")
  calls=$((calls + 1))
  echo "$calls" > "$GIT_CALLS"
  # Simulate partial failure on first clone attempt
  if [[ "$calls" -eq 1 ]]; then
    rm -rf "$dir"
    exit 1
  fi
  mkdir -p "$dir/.git"
  exit 0
fi
exit 0
SH
echo 0 > "$MOCK_DIR/git_calls"
chmod +x "$MOCK_DIR/git"

# make, gcc, wget, install, nproc
for t in make gcc wget nproc pkg-config; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_DIR/$t"
  chmod +x "$MOCK_DIR/$t"
done
# install: copy file
cat > "$MOCK_DIR/install" <<'SH'
#!/usr/bin/env bash
# parse -m 755 src dest
src=""; dest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) shift 2 ;;
    *) if [[ -z "$src" ]]; then src="$1"; else dest="$1"; fi; shift ;;
  esac
done
mkdir -p "$(dirname "$dest")"
cp "$src" "$dest" 2>/dev/null || touch "$dest"
chmod +x "$dest" 2>/dev/null || true
exit 0
SH
chmod +x "$MOCK_DIR/install"

# sudo: pass through
cat > "$MOCK_DIR/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
chmod +x "$MOCK_DIR/sudo"

# iw: report one interface
cat > "$MOCK_DIR/iw" <<'SH'
#!/usr/bin/env bash
echo "Interface wlan0"
exit 0
SH
chmod +x "$MOCK_DIR/iw"

# awk, grep, sort, head, etc. use system ones (already in PATH after mock)
# Ensure system tools available
for t in awk grep sort head cut df timeout bash; do
  if [[ -x "/usr/bin/$t" ]]; then
    ln -sf "/usr/bin/$t" "$MOCK_DIR/$t" 2>/dev/null || true
  elif [[ -x "/bin/$t" ]]; then
    ln -sf "/bin/$t" "$MOCK_DIR/$t" 2>/dev/null || true
  fi
done

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Rerun / idempotency mock test ==="
echo "Mock dir: $MOCK_DIR"
echo

# ---------- Test 1: install/01 (packages) rerun ----------
echo "-- install/01-install-packages.sh --"
if bash "$REPO_ROOT/install/01-install-packages.sh" >/dev/null 2>&1; then
  pass "first run succeeds"
else
  fail "first run failed"
fi
if bash "$REPO_ROOT/install/01-install-packages.sh" >/dev/null 2>&1; then
  pass "rerun succeeds (idempotent)"
else
  fail "rerun failed"
fi

# ---------- Test 2: install/02 (hostapd-mana) partial failure + rerun ----------
echo
echo "-- install/02-build-hostapd-mana.sh (partial failure sim) --"
# Reset git call counter
echo 0 > "$MOCK_DIR/git_calls"
if bash "$REPO_ROOT/install/02-build-hostapd-mana.sh" >/dev/null 2>&1; then
  fail "first run should have failed (simulated partial)"
else
  pass "first run failed as simulated (partial install)"
fi
if bash "$REPO_ROOT/install/02-build-hostapd-mana.sh" >/dev/null 2>&1; then
  pass "rerun succeeds (clone_or_replace retries)"
else
  fail "rerun failed"
fi
# Third run should also succeed (already cloned)
if bash "$REPO_ROOT/install/02-build-hostapd-mana.sh" >/dev/null 2>&1; then
  pass "third run succeeds (already cloned)"
else
  fail "third run failed"
fi

# ---------- Test 3: setup.sh --dry-run (canonical installer) ----------
echo
echo "-- setup.sh --dry-run (canonical installer) --"
if bash "$REPO_ROOT/setup.sh" --dry-run >/dev/null 2>&1; then
  pass "setup.sh --dry-run succeeds"
else
  fail "setup.sh --dry-run failed"
fi
# Rerun
if bash "$REPO_ROOT/setup.sh" --dry-run >/dev/null 2>&1; then
  pass "setup.sh --dry-run rerun succeeds"
else
  fail "setup.sh --dry-run rerun failed"
fi

# ---------- Test 4: setup.sh --quick --dry-run ----------
echo
echo "-- setup.sh --quick --dry-run (quick install) --"
if bash "$REPO_ROOT/setup.sh" --quick --dry-run >/dev/null 2>&1; then
  pass "setup.sh --quick --dry-run succeeds"
else
  fail "setup.sh --quick --dry-run failed"
fi

# ---------- Test 5: install-autopwn-ng.sh --dry-run ----------
echo
echo "-- install-autopwn-ng.sh --dry-run --"
if bash "$REPO_ROOT/install-autopwn-ng.sh" --dry-run >/dev/null 2>&1; then
  pass "install-autopwn-ng.sh --dry-run succeeds"
else
  fail "install-autopwn-ng.sh --dry-run failed"
fi

# ---------- Summary ----------
echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if (( FAIL > 0 )); then
  exit 1
fi
exit 0