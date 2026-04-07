#!/usr/bin/env bash
# Node pool integration test (watchOS Simulator).
#
# watchOS uses a Swift dictionary (unbounded), so this test should
# always pass — it simply confirms that 300 nodes render successfully.
# Requires NODEPOOL_APP to be set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

EXIT_CODE=0

echo "=== Node Pool Test (watchOS) ==="

START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 1

echo "Installing node-pool test app..."
xcrun simctl install "$SIM_UDID" "$NODEPOOL_APP"

echo "Launching node-pool test app..."
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
sleep 8

LOGFILE="$WORK_DIR/log_nodepool_watchos.txt"
get_full_log "$START_TIME" "$LOGFILE"

# Assert: setRoot was called (full UI rendered)
assert_log "$LOGFILE" "setRoot" "setRoot called — full UI rendered"

# Assert: node 300 was created
assert_log "$LOGFILE" "createNode.*-> 300" "All 300 nodes created"

# Uninstall
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
