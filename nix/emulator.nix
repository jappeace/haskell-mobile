# Android emulator test for lifecycle callbacks.
#
# Builds a self-contained script that:
#   1. Boots an Android emulator (auto-detects KVM for acceleration)
#   2. Installs the Haskell Mobile APK
#   3. Launches the activity
#   4. Checks logcat for lifecycle event messages
#
# Usage:
#   nix-build nix/emulator.nix -o result-emulator
#   ./result-emulator/bin/test-lifecycle
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  apk = import ./apk.nix { inherit sources; };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "34" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "x86_64" ];
    cmdLineToolsVersion = "8.0";
  };

  sdk = androidComposition.androidsdk;
  sdkRoot = "${sdk}/libexec/android-sdk";

  platformVersion = "34";
  systemImageType = "google_apis_playstore";
  abiVersion = "x86_64";
  imagePackage = "system-images;android-${platformVersion};${systemImageType};${abiVersion}";

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-emulator-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-lifecycle << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
export ANDROID_SDK_ROOT="${sdkRoot}"
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
AVDMANAGER="${sdk}/bin/avdmanager"
APK_PATH="${apk}/haskell-mobile.apk"
PACKAGE="me.jappie.haskellmobile"
ACTIVITY=".MainActivity"
DEVICE_NAME="test_lifecycle"

# Detect KVM
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM detected -- using hardware acceleration"
    ACCEL_FLAG=""
    BOOT_TIMEOUT=180
else
    echo "No KVM -- using software emulation (slow boot expected)"
    ACCEL_FLAG="-no-accel"
    BOOT_TIMEOUT=900
fi

# --- Temp dirs ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-XXXX)
export HOME="$WORK_DIR/home"
export ANDROID_USER_HOME="$WORK_DIR/user-home"
export ANDROID_AVD_HOME="$WORK_DIR/avd"
export ANDROID_EMULATOR_HOME="$WORK_DIR/emulator-home"
export TMPDIR="$WORK_DIR/tmp"
mkdir -p "$HOME" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME" "$TMPDIR"

# Restart ADB server so it uses our fresh HOME for key generation.
# Without this, a stale ADB server may hold old keys causing
# the emulator to show "unauthorized".
"$ADB" kill-server 2>/dev/null || true
"$ADB" start-server 2>/dev/null || true

LOGCAT_FILE="$WORK_DIR/logcat.txt"
EMU_PID=""

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$EMU_PID" ] && kill -0 "$EMU_PID" 2>/dev/null; then
        echo "Killing emulator (PID $EMU_PID)"
        kill "$EMU_PID" 2>/dev/null || true
        wait "$EMU_PID" 2>/dev/null || true
    fi
    # Also kill via adb
    "$ADB" -s "emulator-$PORT" emu kill 2>/dev/null || true
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

# --- Find free port ---
echo "=== Finding free emulator port ==="
PORT=""
for p in $(seq 5554 2 5584); do
    if ! "$ADB" devices 2>/dev/null | grep -q "emulator-$p"; then
        PORT=$p
        break
    fi
done

if [ -z "$PORT" ]; then
    echo "ERROR: No free emulator port found (5554-5584 all in use)"
    exit 1
fi
echo "Using port: $PORT"
export ANDROID_SERIAL="emulator-$PORT"

# --- Create AVD ---
echo "=== Creating AVD ==="
echo "n" | "$AVDMANAGER" create avd \
    --force \
    --name "$DEVICE_NAME" \
    --package "${imagePackage}" \
    --device "pixel_6" \
    -p "$ANDROID_AVD_HOME/$DEVICE_NAME.avd"

# Configure AVD
cat >> "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini" << 'AVDCONF'
hw.ramSize = 4096
hw.gpu.enabled = yes
hw.gpu.mode = swiftshader_indirect
disk.dataPartition.size = 2G
AVDCONF

# --- Boot emulator ---
echo "=== Booting emulator ==="
"$EMULATOR" \
    -avd "$DEVICE_NAME" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -no-metrics \
    -port "$PORT" \
    -gpu swiftshader_indirect \
    -no-snapshot \
    -memory 4096 \
    $ACCEL_FLAG \
    &
EMU_PID=$!
echo "Emulator PID: $EMU_PID"

# --- Wait for boot ---
# Poll-based wait (adb wait-for-device can fail with protocol faults)
echo "=== Waiting for boot (timeout: ''${BOOT_TIMEOUT}s) ==="
BOOT_DONE=""
ELAPSED=0
while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
    BOOT_DONE=$("$ADB" -s "emulator-$PORT" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || echo "")
    if [ "$BOOT_DONE" = "1" ]; then
        echo "Boot completed after ~''${ELAPSED}s"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    if [ $((ELAPSED % 60)) -eq 0 ]; then
        echo "  Still waiting... (''${ELAPSED}s elapsed)"
    fi
done

if [ "$BOOT_DONE" != "1" ]; then
    echo "ERROR: Emulator failed to boot within ''${BOOT_TIMEOUT}s"
    exit 1
fi

# Wait for device to become fully responsive
echo "Waiting for device to settle..."
sleep 30

# --- Install APK ---
echo "=== Installing APK ==="
INSTALL_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" install -t "$APK_PATH" 2>&1; then
        INSTALL_OK=1
        break
    fi
    echo "Install attempt $attempt failed, retrying in 10s..."
    sleep 10
done

if [ $INSTALL_OK -eq 0 ]; then
    echo "ERROR: Failed to install APK after 3 attempts"
    exit 1
fi
echo "APK installed."

# --- Clear and capture logcat ---
echo "=== Preparing logcat ==="
"$ADB" -s "emulator-$PORT" logcat -c

# Capture all logcat output (we filter later) to catch crashes too
"$ADB" -s "emulator-$PORT" logcat '*:I' > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!

# Small delay to ensure logcat is running
sleep 2

# --- Launch activity ---
echo "=== Launching $PACKAGE/$ACTIVITY ==="
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# Wait for activity to start and log
sleep 10

# --- Poll logcat for lifecycle events ---
echo "=== Checking for lifecycle events (timeout: 120s) ==="
EVENTS=("Lifecycle: Create" "Lifecycle: Start" "Lifecycle: Resume")
POLL_TIMEOUT=120
POLL_ELAPSED=0
ALL_FOUND=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    FOUND_COUNT=0
    for event in "''${EVENTS[@]}"; do
        if grep -q "$event" "$LOGCAT_FILE" 2>/dev/null; then
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

# Kill logcat capture
kill "$LOGCAT_PID" 2>/dev/null || true

# --- Report results ---
echo ""
echo "=== Results ==="
echo "--- HaskellMobile logcat ---"
grep -i "HaskellMobile\|haskellmobile\|loadLibrary\|FATAL\|CRASH\|System.load" "$LOGCAT_FILE" 2>/dev/null || echo "(no matching lines)"
echo "--- End filtered logcat ---"
echo ""

EXIT_CODE=0
for event in "''${EVENTS[@]}"; do
    if grep -q "$event" "$LOGCAT_FILE" 2>/dev/null; then
        echo "PASS: $event"
    else
        echo "FAIL: $event (not found in logcat)"
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

    chmod +x $out/bin/test-lifecycle
  '';

  installPhase = "true";
}
