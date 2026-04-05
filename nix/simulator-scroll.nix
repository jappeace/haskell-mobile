# iOS Simulator ScrollView integration test.
#
# Builds and installs the app with --scroll-demo --autotest, then verifies:
#   1. Haskell emitted a ScrollView node (os_log: createNode(type=5))
#   2. The "Reached Bottom" button callback fired (os_log: Click dispatched: callbackId=0)
#
# The --scroll-demo flag switches the app to scrollDemoApp before the first render.
# The --autotest flag fires event 0 (the "Reached Bottom" button) 3s after render.
#
# Independent from other simulator tests — can run in parallel.
#
# Usage:
#   nix-build nix/simulator-scroll.nix -o result-simulator-scroll
#   ./result-simulator-scroll/bin/test-scroll-ios
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  simulatorApp = import ./simulator-app.nix { inherit sources; };

  xcodegen = pkgs.xcodegen;

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-simulator-scroll-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-scroll-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.haskellmobile"
SCHEME="HaskellMobile"
DEVICE_TYPE="iPhone 16"
SHARE_DIR="${simulatorApp}/share/ios"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-scroll-XXXX)
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

echo "=== iOS Simulator ScrollView Integration Test ==="
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
SIM_UDID=$(xcrun simctl create "test-scroll-ios" "$DEVICE_TYPE" "$RUNTIME" \
    | tr -d '[:space:]')

if [ -z "$SIM_UDID" ]; then
    echo "ERROR: Failed to create simulator device"
    exit 1
fi
echo "Simulator UDID: $SIM_UDID"

echo "=== Booting simulator ==="
xcrun simctl boot "$SIM_UDID"

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
    --predicate "subsystem == \"me.jappie.haskellmobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Give log stream time to fully attach before launching
sleep 5

# --- Launch app with --scroll-demo --autotest ---
echo "=== Launching $BUNDLE_ID with --scroll-demo --autotest ==="
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --scroll-demo --autotest

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

# Retry if log stream missed early messages
if [ $RENDER_DONE -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with app relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --scroll-demo --autotest

    POLL_TIMEOUT=60
    POLL_ELAPSED=0
    while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
        if grep -q "setRoot" "$LOG_FILE" 2>/dev/null; then
            RENDER_DONE=1
            echo "Initial render detected after relaunch (~''${POLL_ELAPSED}s)"
            break
        fi
        sleep 2
        POLL_ELAPSED=$((POLL_ELAPSED + 2))
    done

    if [ $RENDER_DONE -eq 0 ]; then
        echo "WARNING: setRoot not found after retry"
    fi
fi

EXIT_CODE=0

# --- Verify 1: ScrollView node created ---
echo ""
echo "=== Verify 1: ScrollView node created (os_log) ==="
if grep -qE 'createNode\(type=5\)' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: createNode(type=5) found in os_log"
else
    echo "FAIL: createNode(type=5) not found in os_log"
    EXIT_CODE=1
fi

if grep -q 'setRoot' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: setRoot in os_log"
else
    echo "FAIL: setRoot not in os_log"
    EXIT_CODE=1
fi

# --- Wait for auto-tap (3s delay in app) ---
echo ""
echo "=== Waiting for auto-tap callback (timeout: 30s) ==="
POLL_ELAPSED=0
POLL_TIMEOUT=30
TAP_DONE=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q 'Click dispatched: callbackId=0' "$LOG_FILE" 2>/dev/null; then
        TAP_DONE=1
        echo "Click dispatch detected after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

# --- Verify 2: Button callback fired ---
echo ""
echo "=== Verify 2: Button inside ScrollView received click (os_log) ==="
if grep -q 'Click dispatched: callbackId=0' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Click dispatched: callbackId=0 found in os_log"
else
    echo "FAIL: Click dispatched: callbackId=0 not found in os_log"
    EXIT_CODE=1
fi

# Stop log capture
kill "$LOG_PID" 2>/dev/null || true

# --- Report ---
echo ""
echo "=== Filtered log (UIBridge) ==="
grep -i "createNode\|setRoot\|Click dispatched" "$LOG_FILE" 2>/dev/null || echo "(no relevant lines)"
echo "--- End filtered log ---"

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All ScrollView integration checks passed!"
else
    echo "Some ScrollView integration checks failed."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-scroll-ios
  '';

  installPhase = "true";
}
