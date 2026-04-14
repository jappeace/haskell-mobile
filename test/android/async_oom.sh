#!/usr/bin/env bash
# Android async-OOM reproducer (issue #163).
#
# The async package causes the .so to balloon during dlopen, OOM-killing
# the process before any Haskell code executes.  This test installs the
# APK, launches it, and asserts that the app starts successfully.
# Expected result: FAIL (the app never starts — proving the bug).
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, ASYNC_OOM_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$ASYNC_OOM_APK" "async_oom"

# Wait for the platformLog output that proves Haskell code ran.
# Expected: this never arrives because the process is OOM-killed during
# .so loading.
wait_for_logcat "async loaded" 60
WAIT_RC=$?

# --- Diagnostics (always run, even on success) ---
# Temporarily disable errexit so diagnostic commands can't kill the script.
set +e

echo ""
echo "=== async_oom: logcat warnings/errors (last 80 lines) ==="
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:W' 2>&1 | tail -80
echo "=== end async_oom logcat ==="

echo ""
echo "=== async_oom: process status ==="
"$ADB" -s "$EMULATOR_SERIAL" shell "ps -A 2>/dev/null | grep -i jappie || echo 'Process not found (likely killed)'"
echo "=== end process status ==="

# Check for OOM/kill indicators
LOGCAT_OOM="$WORK_DIR/async_oom_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d > "$LOGCAT_OOM" 2>&1
echo ""
echo "=== async_oom: OOM/kill indicators ==="
grep -iE "oom|out of memory|lowmemory|am_kill|am_proc_died|killing|lmk" "$LOGCAT_OOM" | grep -i "jappie\|hatter\|oom\|kill\|memory" | tail -20 || echo "(none found)"
echo "=== end OOM indicators ==="

# Check for native crash indicators
echo ""
echo "=== async_oom: native crash indicators ==="
grep -E "UnsatisfiedLinkError|dlopen failed|cannot locate symbol|SIGABRT|SIGSEGV|Fatal signal" "$LOGCAT_OOM" | tail -10 || echo "(none found)"
echo "=== end native crash indicators ==="

set -e
# --- End diagnostics ---

if [ $WAIT_RC -eq 2 ]; then
    echo ""
    echo "FATAL: Native library failed to load (expected for async OOM reproducer)"
    EXIT_CODE=1
elif [ $WAIT_RC -eq 1 ]; then
    echo ""
    echo "FAIL: Timed out waiting for 'async loaded' (app likely OOM-killed)"
    EXIT_CODE=1
fi

# Collect final logcat
collect_logcat "async_oom"

# Assert the app actually started (this is the key assertion — it should FAIL)
assert_logcat "$LOGCAT_FILE" "async loaded" "async package loaded successfully"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
