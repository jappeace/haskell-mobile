#!/usr/bin/env bash
# Node pool integration test (Android).
#
# Verifies that all 300 nodes render without pool exhaustion.
# Requires NODEPOOL_APK (built with dynamicNodePool=true) to be set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

EXIT_CODE=0

echo "=== Node Pool Test ==="

start_app "$NODEPOOL_APK" "nodepool"

# Wait for setRoot (full UI rendered)
wait_for_logcat "setRoot" 30 || true

collect_logcat "nodepool"

# Assert: setRoot was called (full UI rendered)
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called — full UI rendered"

# Assert: node 300 was created (1 Column + 299 Text = 300 nodes)
assert_logcat "$LOGCAT_FILE" "createNode.*-> 300" "All 300 nodes created"

# Assert: no pool exhaustion
if grep -q "Node pool exhausted" "$LOGCAT_FILE" 2>/dev/null; then
    echo "FAIL: Node pool exhaustion detected"
    EXIT_CODE=1
else
    echo "PASS: No pool exhaustion"
fi

# Uninstall
"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
