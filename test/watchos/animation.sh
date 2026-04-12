#!/usr/bin/env bash
# watchOS animation test: install animation app, launch,
# verify the animation bridge fires callbacks (uses desktop stub).
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIMCTL, DEVICE_ID, ANIMATION_APP, WORK_DIR
set -euo pipefail

EXIT_CODE=0

echo "--- Installing animation app ---"
xcrun simctl install "$DEVICE_ID" "$ANIMATION_APP" || { echo "FAIL: install"; exit 1; }
xcrun simctl launch --console "$DEVICE_ID" me.jappie.haskellmobile > "$WORK_DIR/animation_log.txt" 2>&1 &
APP_PID=$!
sleep 5

# Check log output for animation activity
if grep -q "setRoot\|AnimationDemoMain" "$WORK_DIR/animation_log.txt" 2>/dev/null; then
    echo "PASS: Animation app rendered"
else
    echo "FAIL: Animation app did not render"
    EXIT_CODE=1
fi

kill "$APP_PID" 2>/dev/null || true
xcrun simctl uninstall "$DEVICE_ID" me.jappie.haskellmobile 2>/dev/null || true

exit $EXIT_CODE
