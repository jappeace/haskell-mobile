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

start_app "$NODEPOOL_APP" "nodepool"
sleep 8

LOGFILE="$WORK_DIR/log_nodepool_watchos.txt"
get_full_log "$APP_START_TIME" "$LOGFILE"

# Assert: setRoot was called (full UI rendered)
assert_log "$LOGFILE" "setRoot" "setRoot called — full UI rendered"

# Assert: node 300 was created
assert_log "$LOGFILE" "createNode.*-> 300" "All 300 nodes created"

cleanup_app

exit $EXIT_CODE
