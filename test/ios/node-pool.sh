#!/usr/bin/env bash
# Node pool integration test (iOS Simulator).
#
# Verifies that all 300 nodes render without pool exhaustion.
# Requires NODEPOOL_APP to be set (built with dynamicNodePool=true).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

EXIT_CODE=0

echo "=== Node Pool Test (iOS) ==="

START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 1

echo "Installing node-pool test app..."
xcrun simctl install "$SIM_UDID" "$NODEPOOL_APP"

echo "Launching node-pool test app..."
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
sleep 8

LOGFILE="$WORK_DIR/log_nodepool_ios.txt"
get_full_log "$START_TIME" "$LOGFILE"

# Assert: setRoot was called (full UI rendered)
assert_log "$LOGFILE" "setRoot" "setRoot called — full UI rendered"

# Assert: node 300 was created
assert_log "$LOGFILE" "createNode.*-> 300" "All 300 nodes created"

# Assert: no pool exhaustion
if grep -qE "Node pool exhausted" "$LOGFILE" 2>/dev/null; then
    echo "FAIL: Node pool exhaustion detected"
    EXIT_CODE=1
else
    echo "PASS: No pool exhaustion"
fi

# Uninstall
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
