# iOS Simulator test for lifecycle callbacks.
#
# Uses simulator-app.nix for staged sources, then provides a test script that:
#   1. Generates an Xcode project with xcodegen
#   2. Builds the app with xcodebuild for iphonesimulator
#   3. Boots an iOS Simulator, installs the .app, launches it
#   4. Captures os_log output and checks for lifecycle events
#
# Usage:
#   nix-build nix/simulator.nix -o result-simulator
#   ./result-simulator/bin/test-lifecycle-ios
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  simulatorApp = import ./simulator-app.nix { inherit sources; };

  xcodegen = pkgs.xcodegen;

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-simulator-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-lifecycle-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.haskellmobile"
SCHEME="HaskellMobile"
DEVICE_TYPE="iPhone 16"
SHARE_DIR="${simulatorApp}/share/ios"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-XXXX)
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

echo "=== iOS Simulator Lifecycle Test ==="
echo "Working directory: $WORK_DIR"

# --- Stage library and sources ---
echo "=== Staging Xcode project ==="
mkdir -p "$WORK_DIR/ios/lib" "$WORK_DIR/ios/include"
cp "$SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/ios/lib/"
cp "$SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/ios/include/"
cp "$SHARE_DIR/include/UIBridge.h" "$WORK_DIR/ios/include/"
cp -r "$SHARE_DIR/HaskellMobile" "$WORK_DIR/ios/"
cp "$SHARE_DIR/project.yml" "$WORK_DIR/ios/"
# Nix store files are read-only; make writable so cleanup and xcodebuild work
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
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$WORK_DIR/build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
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
SIM_UDID=$(xcrun simctl create "test-lifecycle-ios" "$DEVICE_TYPE" "$RUNTIME" \
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

# Capture os_log output for our process.
# --level info: OS_LOG_TYPE_INFO is not streamed by default (only default+error).
# composedMessage: eventMessage has the format template, composedMessage has actual text.
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "process == \"HaskellMobile\" AND composedMessage CONTAINS \"Lifecycle:\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Give log stream a moment to attach
sleep 2

# --- Launch app ---
echo "=== Launching $BUNDLE_ID ==="
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

# --- Poll for lifecycle events ---
echo "=== Checking for lifecycle events (timeout: 60s) ==="
EVENTS=("Lifecycle: Create" "Lifecycle: Resume")
POLL_TIMEOUT=60
POLL_ELAPSED=0
ALL_FOUND=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    FOUND_COUNT=0
    for event in "''${EVENTS[@]}"; do
        if grep -q "$event" "$LOG_FILE" 2>/dev/null; then
            FOUND_COUNT=$((FOUND_COUNT + 1))
        fi
    done

    if [ $FOUND_COUNT -eq ''${#EVENTS[@]} ]; then
        ALL_FOUND=1
        break
    fi

    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

# Stop log capture
kill "$LOG_PID" 2>/dev/null || true

# --- Report results ---
echo ""
echo "=== Results ==="
echo "--- Captured log ---"
cat "$LOG_FILE" 2>/dev/null || echo "(no log output)"
echo "--- End log ---"
echo ""

EXIT_CODE=0
for event in "''${EVENTS[@]}"; do
    if grep -q "$event" "$LOG_FILE" 2>/dev/null; then
        echo "PASS: $event"
    else
        echo "FAIL: $event (not found in os_log)"
        EXIT_CODE=1
    fi
done

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All lifecycle events verified successfully!"
else
    echo "Some lifecycle events were not detected."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-lifecycle-ios
  '';

  installPhase = "true";
}
