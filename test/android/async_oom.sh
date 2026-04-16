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

# NOTE: we intentionally use set -uo pipefail WITHOUT -e here.
# With errexit, diagnostic commands that find nothing (grep returns 1)
# would kill the script before we can report what happened.
set -uo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# Enable bionic linker debug output for dlopen diagnostics.
"$ADB" -s "$EMULATOR_SERIAL" shell "setprop debug.ld.all dlerror" 2>/dev/null || true

start_app "$ASYNC_OOM_APK" "async_oom"

# Start a background memory monitor on the device that polls /proc/PID/status
# every 0.5s and logs VmSize/VmRSS/VmPeak.
# shellcheck disable=SC2016  # single quotes intentional — runs on device
"$ADB" -s "$EMULATOR_SERIAL" shell '
  while true; do
    PID=$(pidof me.jappie.hatter 2>/dev/null)
    if [ -n "$PID" ]; then
      STAMP=$(date +%s)
      MEM=$(grep -E "VmSize|VmRSS|VmPeak" /proc/$PID/status 2>/dev/null | tr "\n" " ")
      echo "$STAMP $MEM"
    fi
    sleep 0.5
  done
' > "$WORK_DIR/memory_timeline.txt" 2>/dev/null &
MEMORY_MONITOR_PID=$!

# Wait for the platformLog output that proves Haskell code ran.
# Expected: this never arrives because the process is OOM-killed during
# .so loading.
wait_for_logcat "async loaded" 60
WAIT_RC=$?

# Stop the background memory monitor.
kill "$MEMORY_MONITOR_PID" 2>/dev/null || true
wait "$MEMORY_MONITOR_PID" 2>/dev/null || true

# --- Diagnostics (always run) ---
echo ""
echo "=== async_oom: logcat warnings/errors (last 80 lines) ==="
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:W' 2>&1 | tail -80 || true
echo "=== end async_oom logcat ==="

echo ""
echo "=== async_oom: process status ==="
"$ADB" -s "$EMULATOR_SERIAL" shell "ps -A 2>/dev/null | grep -i jappie || echo 'Process not found (likely killed)'" || true
echo "=== end process status ==="

# Check for OOM/kill indicators
LOGCAT_OOM="$WORK_DIR/async_oom_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d > "$LOGCAT_OOM" 2>&1 || true
echo ""
echo "=== async_oom: OOM/kill indicators ==="
grep -iE "oom|out of memory|lowmemory|am_kill|am_proc_died|killing|lmk" "$LOGCAT_OOM" | grep -i "jappie\|hatter\|oom\|kill\|memory" | tail -20 || echo "(none found)"
echo "=== end OOM indicators ==="

# Check for native crash indicators
echo ""
echo "=== async_oom: native crash indicators ==="
grep -E "UnsatisfiedLinkError|dlopen failed|cannot locate symbol|SIGABRT|SIGSEGV|Fatal signal" "$LOGCAT_OOM" | tail -10 || echo "(none found)"
echo "=== end native crash indicators ==="

# HatterOOM debug checkpoints (from jni_bridge.c instrumentation)
echo ""
echo "=== async_oom: HatterOOM memory checkpoints ==="
grep "HatterOOM" "$LOGCAT_OOM" | tail -30 || echo "(none found — DEBUG_OOM may not be enabled)"
echo "=== end HatterOOM checkpoints ==="

# Linker debug output
echo ""
echo "=== async_oom: linker debug output ==="
grep -i "linker\|dlopen\|dlsym" "$LOGCAT_OOM" | tail -20 || echo "(none found)"
echo "=== end linker debug ==="

# Memory timeline from background monitor
echo ""
echo "=== async_oom: memory timeline ==="
if [ -s "$WORK_DIR/memory_timeline.txt" ]; then
    cat "$WORK_DIR/memory_timeline.txt"
else
    echo "(no data captured — process may have died too quickly)"
fi
echo "=== end memory timeline ==="

# Dump /proc/PID/smaps if the process is still alive
echo ""
echo "=== async_oom: smaps (top 10 by RSS) ==="
# shellcheck disable=SC2016  # single quotes intentional — runs on device
"$ADB" -s "$EMULATOR_SERIAL" shell '
  PID=$(pidof me.jappie.hatter 2>/dev/null)
  if [ -n "$PID" ]; then
    cat /proc/$PID/smaps 2>/dev/null | \
      awk "/^[0-9a-f]/{region=\$0} /^Rss:/{print \$2, region}" | \
      sort -rn | head -10
  else
    echo "(process not running)"
  fi
' 2>/dev/null || echo "(smaps unavailable)"
echo "=== end smaps ==="
# --- End diagnostics ---

if [ "$WAIT_RC" -eq 2 ]; then
    echo ""
    echo "FATAL: Native library failed to load (expected for async OOM reproducer)"
    EXIT_CODE=1
elif [ "$WAIT_RC" -eq 1 ]; then
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
