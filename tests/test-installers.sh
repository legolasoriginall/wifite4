#!/usr/bin/env bash
# ==========================================================================
#  Regression tests: ensure_root() must re-exec with the original flags.
#  Mocks sudo so nothing actually escalates; only the argv is recorded.
#  Usage: bash tests/test-installers.sh
# ==========================================================================
set -uo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "SKIP: run as non-root — root skips ensure_root's sudo re-exec."
  exit 0
fi

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
cp "$REPO_ROOT/setup.sh" "$REPO_ROOT/uninstall.sh" "$FIX/"
mkdir -p "$FIX/install"
cp "$REPO_ROOT/install/common.sh" "$FIX/install/"

MOCK="$FIX/mock"
mkdir -p "$MOCK"
cat > "$MOCK/sudo" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
exit 0
MOCK
chmod +x "$MOCK/sudo"

check_reexec() {
  local desc="$1" script="$2" expected="$3"; shift 3
  local log="$FIX/sudo.log" rc
  : > "$log"
  SUDO_LOG="$log" PATH="$MOCK:$PATH" bash "$FIX/$script" "$@" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] && grep -qxF -- "$expected" "$log"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (rc=$rc, sudo calls: $(tr '\n' '|' < "$log"))"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== installer sudo re-exec tests (mocked sudo) ==="
check_reexec "setup.sh keeps --quick" setup.sh \
  "-n bash $FIX/setup.sh --quick" --quick
check_reexec "uninstall.sh keeps --keep-wordlists" uninstall.sh \
  "-n bash $FIX/uninstall.sh --keep-wordlists" --keep-wordlists

echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

(( FAIL > 0 )) && exit 1
exit 0
