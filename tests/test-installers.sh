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
echo "-- hostapd-mana build --"
BUILD_FIX="$(mktemp -d)"
BUILD_PREFIX="$(mktemp -d)"
mkdir -p "$BUILD_FIX/install" "$BUILD_PREFIX/opt/hostapd-mana/.git" "$BUILD_PREFIX/opt/hostapd-mana/hostapd" "$BUILD_PREFIX/usr/local/bin"
cp "$REPO_ROOT/install/common.sh" "$REPO_ROOT/install/02-build-hostapd-mana.sh" "$BUILD_FIX/install/"
printf 'CONFIG_DRIVER_NL80211=y\n' > "$BUILD_PREFIX/opt/hostapd-mana/hostapd/defconfig"
BUILD_MOCK="$BUILD_FIX/mock"
mkdir -p "$BUILD_MOCK"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BUILD_MOCK/apt-get"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BUILD_MOCK/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BUILD_MOCK/install"
cat > "$BUILD_MOCK/make" <<'MOCK'
#!/usr/bin/env bash
dir=""
while [ $# -gt 0 ]; do case "$1" in -C) dir="$2"; shift 2;; -j*) shift;; *) shift;; esac; done
[ -f "$dir/.config" ] || { echo 'No .config file found' >&2; exit 1; }
printf '%s\n' "$dir" >> "$MAKE_LOG"
exit 0
MOCK
chmod +x "$BUILD_MOCK"/*
MAKE_LOG="$BUILD_FIX/make.log" PATH="$BUILD_MOCK:$PATH" WIFITE4_TEST_MODE=1 WIFITE4_PREFIX="$BUILD_PREFIX" \
  bash "$BUILD_FIX/install/02-build-hostapd-mana.sh" >/dev/null 2>&1
BUILD_RC=$?
if [ "$BUILD_RC" -eq 0 ] && [ -f "$BUILD_PREFIX/opt/hostapd-mana/hostapd/.config" ] \
   && grep -qxF "$BUILD_PREFIX/opt/hostapd-mana/hostapd" "$BUILD_FIX/make.log"; then
  echo "  PASS: builds with a .config created from defconfig"; PASS=$((PASS + 1))
else
  echo "  FAIL: hostapd build (rc=$BUILD_RC, config=$([ -f "$BUILD_PREFIX/opt/hostapd-mana/hostapd/.config" ] && echo yes || echo no))"
  FAIL=$((FAIL + 1))
fi
rm -rf "$BUILD_FIX" "$BUILD_PREFIX"

echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

(( FAIL > 0 )) && exit 1
exit 0
