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

# --- Wait for auto-tap sequence ---
# The --autotest-buttons flag fires: +3s, +5s, +7s, +9s, +11s
# Total sequence takes ~11s from render. We poll for each expected value.

# Helper: wait for a counter value to appear N times in the log
# Usage: wait_for_value PATTERN LABEL [MIN_COUNT]
wait_for_value() {
    local PATTERN="$1"
    local LABEL="$2"
    local MIN_COUNT="''${3:-1}"
    local TIMEOUT=30
    local ELAPSED=0

    echo ""
    echo "=== Waiting for $LABEL (timeout: ''${TIMEOUT}s) ==="
    while [ $ELAPSED -lt $TIMEOUT ]; do
        local COUNT
        COUNT=$(grep -c "setStrProp.*$PATTERN" "$LOG_FILE" 2>/dev/null || echo "0")
        if [ "$COUNT" -ge "$MIN_COUNT" ]; then
            echo "  Detected '$PATTERN' (count=$COUNT) after ~''${ELAPSED}s"
            return 0
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    echo "  WARNING: '$PATTERN' not found ''${MIN_COUNT} time(s) after ''${TIMEOUT}s"
    return 1
}

# Step 1: + → Counter: 1  (at +3s)
wait_for_value "Counter: 1" "first + tap → Counter: 1"
if grep -q 'setStrProp.*Counter: 1' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Counter: 1 after first + tap"
else
    echo "FAIL: Counter: 1 after first + tap"
    EXIT_CODE=1
fi

# Step 2: + → Counter: 2  (at +5s)
wait_for_value "Counter: 2" "second + tap → Counter: 2"
if grep -q 'setStrProp.*Counter: 2' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Counter: 2 after second + tap"
else
    echo "FAIL: Counter: 2 after second + tap"
    EXIT_CODE=1
fi

# Step 3: - → Counter: 1  (at +7s — second occurrence)
# We need to wait for Counter: 1 to appear again after Counter: 2
wait_for_value "Counter: 1" "first - tap → Counter: 1 (again)" 2
COUNT_1=$(grep -c 'setStrProp.*Counter: 1' "$LOG_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_1" -ge 2 ]; then
    echo "PASS: Counter: 1 after first - tap (seen $COUNT_1 times)"
else
    echo "FAIL: Counter: 1 after first - tap (seen $COUNT_1 times, expected >=2)"
    EXIT_CODE=1
fi

# Step 4: - → Counter: 0  (at +9s — second occurrence)
wait_for_value "Counter: 0" "second - tap → Counter: 0 (again)" 2
COUNT_0=$(grep -c 'setStrProp.*Counter: 0' "$LOG_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_0" -ge 2 ]; then
    echo "PASS: Counter: 0 after second - tap (seen $COUNT_0 times)"
else
    echo "FAIL: Counter: 0 after second - tap (seen $COUNT_0 times, expected >=2)"
    EXIT_CODE=1
fi

# Step 5: - → Counter: -1  (at +11s)
wait_for_value "Counter: -1" "third - tap → Counter: -1"
if grep -q 'setStrProp.*Counter: -1' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Counter: -1 after third - tap"
else
    echo "FAIL: Counter: -1 after third - tap"
    EXIT_CODE=1
fi

# Stop log capture
kill "$LOG_PID" 2>/dev/null || true

# --- Report ---
echo ""
echo "=== Filtered log (UIBridge) ==="
grep -i "UIBridge\|setRoot\|setStrProp\|setHandler\|Click dispatched\|Counter:" "$LOG_FILE" 2>/dev/null || echo "(no relevant lines)"
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
