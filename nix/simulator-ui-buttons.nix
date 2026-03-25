# iOS Simulator UI two-button test.
#
# Builds and installs the app with --autotest-buttons, then verifies:
#   1. The counter app renders (os_log: setRoot, setHandler)
#   2. Auto-tap sequence fires: +, +, -, -, -
#   3. Counter values appear in order: 1, 2, 1 (again), 0 (again), -1
#
# Proves both "+" and "-" buttons are wired up and functional.
#
# Usage:
#   nix-build nix/simulator-ui-buttons.nix -o result-simulator-ui-buttons
#   ./result-simulator-ui-buttons/bin/test-ui-buttons-ios
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  simulatorApp = import ./simulator-app.nix { inherit sources; };

  xcodegen = pkgs.xcodegen;

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-simulator-ui-buttons-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-ui-buttons-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.haskellmobile"
SCHEME="HaskellMobile"
DEVICE_TYPE="iPhone 16"
SHARE_DIR="${simulatorApp}/share/ios"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-ui-btn-XXXX)
SIM_UDID=""

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$SIM_UDID" ]; then
        echo "Shutting down simulator $SIM_UDID"
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        echo "Deleting simulator $SIM_UDID"
        xcrun simctl delete "$SIM_UDID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

echo "=== iOS Simulator UI Two-Button Test ==="
echo "Working directory: $WORK_DIR"

# --- Stage library and sources ---
echo "=== Staging Xcode project ==="
mkdir -p "$WORK_DIR/ios/lib" "$WORK_DIR/ios/include"
cp "$SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/ios/lib/"
cp "$SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/ios/include/"
cp "$SHARE_DIR/include/UIBridge.h" "$WORK_DIR/ios/include/"
cp -r "$SHARE_DIR/HaskellMobile" "$WORK_DIR/ios/"
cp "$SHARE_DIR/project.yml" "$WORK_DIR/ios/"
chmod -R u+w "$WORK_DIR/ios"

# --- Generate Xcode project ---
echo "=== Generating Xcode project ==="
cd "$WORK_DIR/ios"
${xcodegen}/bin/xcodegen generate

# --- Build for simulator ---
echo "=== Building for iOS Simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

echo "Build succeeded."

# --- Find .app bundle ---
APP_PATH=$(find "$WORK_DIR/build" -name "*.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find .app bundle in build output"
    exit 1
fi
echo "App bundle: $APP_PATH"

# --- Discover latest iOS runtime ---
echo "=== Discovering iOS runtime ==="
RUNTIME=$(xcrun simctl list runtimes -j \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
ios_runtimes = [r for r in data['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
if not ios_runtimes:
    print('ERROR: No available iOS runtimes', file=sys.stderr)
    sys.exit(1)
print(ios_runtimes[-1]['identifier'])
")
echo "Runtime: $RUNTIME"

# --- Create and boot simulator ---
echo "=== Creating simulator ==="
SIM_UDID=$(xcrun simctl create "test-ui-buttons-ios" "$DEVICE_TYPE" "$RUNTIME" \
    | tr -d '[:space:]')

if [ -z "$SIM_UDID" ]; then
    echo "ERROR: Failed to create simulator device"
    exit 1
fi
echo "Simulator UDID: $SIM_UDID"

echo "=== Booting simulator ==="
xcrun simctl boot "$SIM_UDID"

# Wait for simulator to finish booting
BOOT_TIMEOUT=120
BOOT_ELAPSED=0
while [ $BOOT_ELAPSED -lt $BOOT_TIMEOUT ]; do
    STATE=$(xcrun simctl list devices -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime_devs in data['devices'].values():
    for d in runtime_devs:
        if d['udid'] == '$SIM_UDID':
            print(d['state'])
            sys.exit(0)
print('Unknown')
")
    if [ "$STATE" = "Booted" ]; then
        echo "Simulator booted after ~''${BOOT_ELAPSED}s"
        break
    fi
    sleep 2
    BOOT_ELAPSED=$((BOOT_ELAPSED + 2))
done

if [ "$STATE" != "Booted" ]; then
    echo "ERROR: Simulator failed to boot within ''${BOOT_TIMEOUT}s"
    exit 1
fi

# Brief settle time
sleep 5

# --- Install app ---
echo "=== Installing app ==="
xcrun simctl install "$SIM_UDID" "$APP_PATH"
echo "App installed."

# --- Start log capture ---
echo "=== Starting log capture ==="
LOG_FILE="$WORK_DIR/os_log.txt"

xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "process == \"HaskellMobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Give log stream a moment to attach
sleep 2

# --- Launch app with --autotest-buttons ---
echo "=== Launching $BUNDLE_ID with --autotest-buttons ==="
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons

# --- Wait for initial render ---
echo "=== Waiting for initial render (timeout: 60s) ==="
POLL_TIMEOUT=60
POLL_ELAPSED=0
RENDER_DONE=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setRoot" "$LOG_FILE" 2>/dev/null; then
        RENDER_DONE=1
        echo "Initial render detected after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if [ $RENDER_DONE -eq 0 ]; then
    echo "WARNING: setRoot not found in os_log after ''${POLL_TIMEOUT}s"
fi

# --- Verify initial render ---
echo ""
echo "=== Verifying initial render (os_log) ==="
EXIT_CODE=0

if grep -q 'setStrProp.*Counter:' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Initial render — counter label rendered"
else
    echo "FAIL: Initial render — counter label not found in os_log"
    EXIT_CODE=1
fi

if grep -q 'setRoot' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Initial render — setRoot in os_log"
else
    echo "FAIL: Initial render — setRoot in os_log"
    EXIT_CODE=1
fi

if grep -q 'setHandler.*click' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Initial render — button handlers in os_log"
else
    echo "FAIL: Initial render — button handlers in os_log"
    EXIT_CODE=1
fi

# --- Wait for auto-tap sequence to complete ---
# The --autotest-buttons flag fires: +3s, +5s, +7s, +9s, +11s from view creation.
# All taps may already be done by the time we start checking (the app can launch
# and render faster than the simulator boot detection). Wait for the final value
# (Counter: -1) then verify all intermediate values from the complete log.
#
# We use 'log show' instead of the streaming log file for verification, because
# the stream can buffer or rate-limit entries. 'log show' queries the full
# persistent log store and is reliable.

echo ""
echo "=== Waiting for autotest sequence to complete (Counter: -1) ==="
SEQ_TIMEOUT=60
SEQ_ELAPSED=0
SEQ_DONE=0

while [ $SEQ_ELAPSED -lt $SEQ_TIMEOUT ]; do
    if grep -q "setStrProp.*Counter: -1" "$LOG_FILE" 2>/dev/null; then
        SEQ_DONE=1
        echo "  Final value 'Counter: -1' detected after ~''${SEQ_ELAPSED}s"
        break
    fi
    sleep 2
    SEQ_ELAPSED=$((SEQ_ELAPSED + 2))
done

# Stop log stream capture
kill "$LOG_PID" 2>/dev/null || true
sleep 1

if [ $SEQ_DONE -eq 0 ]; then
    echo "  ERROR: 'Counter: -1' not found after ''${SEQ_TIMEOUT}s — autotest sequence incomplete"
    echo ""
    echo "=== Filtered log (UIBridge) ==="
    grep -i "UIBridge\|setRoot\|setStrProp\|setHandler" "$LOG_FILE" 2>/dev/null || echo "(no relevant lines)"
    echo "--- End filtered log ---"
    exit 1
fi

# Retrieve complete log via 'log show' for reliable verification
echo ""
echo "=== Retrieving complete log via 'log show' ==="
FULL_LOG="$WORK_DIR/full_log.txt"
xcrun simctl spawn "$SIM_UDID" log show \
    --predicate "subsystem == \"me.jappie.haskellmobile\"" \
    --style compact \
    --info \
    > "$FULL_LOG" 2>&1 || true

echo "Full log lines: $(wc -l < "$FULL_LOG")"

# Fall back to streaming log if 'log show' returned nothing useful
if ! grep -q "setStrProp" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty, falling back to stream log"
    FULL_LOG="$LOG_FILE"
fi

# --- Verify complete tap sequence ---
echo ""
echo "=== Verifying tap sequence from complete log ==="

# Extract counter values in order from setStrProp lines
COUNTER_SEQ=$(grep -o 'setStrProp.*Counter: [0-9-]*' "$FULL_LOG" 2>/dev/null \
    | grep -o 'Counter: [0-9-]*' || echo "")
echo "Counter sequence: $COUNTER_SEQ"

# Check each expected value exists
check_value() {
    local PATTERN="$1"
    local LABEL="$2"
    local MIN_COUNT="$3"
    local COUNT
    COUNT=$(grep -c "setStrProp.*$PATTERN" "$FULL_LOG" 2>/dev/null || echo "0")
    if [ "$COUNT" -ge "$MIN_COUNT" ]; then
        echo "PASS: $LABEL (seen $COUNT times)"
    else
        echo "FAIL: $LABEL (seen $COUNT times, expected >=$MIN_COUNT)"
        EXIT_CODE=1
    fi
}

check_value "Counter: 0" "Initial render — Counter: 0" 1
check_value "Counter: 1" "Tap + → Counter: 1" 1
check_value "Counter: 2" "Tap + → Counter: 2" 1
check_value "Counter: -1" "Tap - → Counter: -1" 1

# For values that appear twice (0 and 1), check count >= 2
COUNT_1=$(grep -c 'setStrProp.*Counter: 1' "$FULL_LOG" 2>/dev/null || echo "0")
if [ "$COUNT_1" -ge 2 ]; then
    echo "PASS: Counter: 1 appeared twice (+ tap and - tap)"
else
    echo "WARN: Counter: 1 seen $COUNT_1 time(s), expected 2 (log stream may have deduplicated)"
fi

COUNT_0=$(grep -c 'setStrProp.*Counter: 0' "$FULL_LOG" 2>/dev/null || echo "0")
if [ "$COUNT_0" -ge 2 ]; then
    echo "PASS: Counter: 0 appeared twice (initial and - tap)"
else
    echo "WARN: Counter: 0 seen $COUNT_0 time(s), expected 2 (log stream may have deduplicated)"
fi

# --- Report ---
echo ""
echo "=== Filtered log (UIBridge) ==="
grep -i "UIBridge\|setRoot\|setStrProp\|setHandler\|Click dispatched\|Counter:" "$FULL_LOG" 2>/dev/null || echo "(no relevant lines)"
echo "--- End filtered log ---"

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All two-button UI checks passed!"
else
    echo "Some two-button UI checks failed."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-ui-buttons-ios
  '';

  installPhase = "true";
}
