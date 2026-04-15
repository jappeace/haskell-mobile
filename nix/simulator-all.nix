# iOS Simulator combined integration test.
#
# Single simulator session covering all test suites:
#
#   Phase 1 — Counter app (lifecycle + UI rendering + two-button sequence)
#     Verifies: Lifecycle: Create/Resume, setRoot/setStrProp/setHandler,
#               --autotest fires Counter: 1, --autotest-buttons fires full sequence.
#
#   Phase 2 — Scroll demo app
#     Verifies: createNode(type=5), setRoot, Click dispatched: callbackId=0.
#
# One boot + teardown cycle instead of four.
#
# Usage:
#   nix-build nix/simulator-all.nix -o result-simulator-all
#   ./result-simulator-all/bin/test-all-ios
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  lib = import ./lib.nix { inherit sources; };

  counterIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/CounterDemoMain.hs;
    simulator = true;
  };
  counterSimApp = lib.mkSimulatorApp {
    iosLib = counterIos;
    iosSrc = ../ios;
    name = "hatter-simulator-app";
  };

  scrollIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/ScrollDemoMain.hs;
    simulator = true;
  };
  scrollSimApp = lib.mkSimulatorApp {
    iosLib = scrollIos;
    iosSrc = ../ios;
    name = "hatter-scroll-simulator-app";
  };

  textinputIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/TextInputDemoMain.hs;
    simulator = true;
  };
  textinputSimApp = lib.mkSimulatorApp {
    iosLib = textinputIos;
    iosSrc = ../ios;
    name = "hatter-textinput-simulator-app";
  };

  permissionIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/PermissionDemoMain.hs;
    simulator = true;
  };
  permissionSimApp = lib.mkSimulatorApp {
    iosLib = permissionIos;
    iosSrc = ../ios;
    name = "hatter-permission-simulator-app";
  };

  secureStorageIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/SecureStorageDemoMain.hs;
    simulator = true;
  };
  secureStorageSimApp = lib.mkSimulatorApp {
    iosLib = secureStorageIos;
    iosSrc = ../ios;
    name = "hatter-securestorage-simulator-app";
  };

  imageIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/ImageDemoMain.hs;
    simulator = true;
  };
  imageSimApp = lib.mkSimulatorApp {
    iosLib = imageIos;
    iosSrc = ../ios;
    name = "hatter-image-simulator-app";
  };

  nodepoolIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/NodePoolTestMain.hs;
    simulator = true;
  };
  nodepoolSimApp = lib.mkSimulatorApp {
    iosLib = nodepoolIos;
    iosSrc = ../ios;
    name = "hatter-nodepool-simulator-app";
    dynamicNodePool = true;
  };

  bleIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/BleDemoMain.hs;
    simulator = true;
  };
  bleSimApp = lib.mkSimulatorApp {
    iosLib = bleIos;
    iosSrc = ../ios;
    name = "hatter-ble-simulator-app";
  };

  dialogIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/DialogDemoMain.hs;
    simulator = true;
  };
  dialogSimApp = lib.mkSimulatorApp {
    iosLib = dialogIos;
    iosSrc = ../ios;
    name = "hatter-dialog-simulator-app";
  };

  locationIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/LocationDemoMain.hs;
    simulator = true;
  };
  locationSimApp = lib.mkSimulatorApp {
    iosLib = locationIos;
    iosSrc = ../ios;
    name = "hatter-location-simulator-app";
  };

  webviewIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/WebViewDemoMain.hs;
    simulator = true;
  };
  webviewSimApp = lib.mkSimulatorApp {
    iosLib = webviewIos;
    iosSrc = ../ios;
    name = "hatter-webview-simulator-app";
  };

  authSessionIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/AuthSessionDemoMain.hs;
    simulator = true;
  };
  authSessionSimApp = lib.mkSimulatorApp {
    iosLib = authSessionIos;
    iosSrc = ../ios;
    name = "hatter-authsession-simulator-app";
  };

  platformSignInIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/PlatformSignInDemoMain.hs;
    simulator = true;
  };
  platformSignInSimApp = lib.mkSimulatorApp {
    iosLib = platformSignInIos;
    iosSrc = ../ios;
    name = "hatter-platformsignin-simulator-app";
  };

  cameraIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/CameraDemoMain.hs;
    simulator = true;
  };
  cameraSimApp = lib.mkSimulatorApp {
    iosLib = cameraIos;
    iosSrc = ../ios;
    name = "hatter-camera-simulator-app";
  };

  bottomSheetIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/BottomSheetDemoMain.hs;
    simulator = true;
  };
  bottomSheetSimApp = lib.mkSimulatorApp {
    iosLib = bottomSheetIos;
    iosSrc = ../ios;
    name = "hatter-bottomsheet-simulator-app";
  };

  httpIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/HttpDemoMain.hs;
    simulator = true;
  };
  httpSimApp = lib.mkSimulatorApp {
    iosLib = httpIos;
    iosSrc = ../ios;
    name = "hatter-http-simulator-app";
  };

  networkStatusIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/NetworkStatusDemoMain.hs;
    simulator = true;
  };
  networkStatusSimApp = lib.mkSimulatorApp {
    iosLib = networkStatusIos;
    iosSrc = ../ios;
    name = "hatter-networkstatus-simulator-app";
  };

  mapviewIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/MapViewDemoMain.hs;
    simulator = true;
  };
  mapviewSimApp = lib.mkSimulatorApp {
    iosLib = mapviewIos;
    iosSrc = ../ios;
    name = "hatter-mapview-simulator-app";
  };

  animationIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/AnimationDemoMain.hs;
    simulator = true;
  };
  animationSimApp = lib.mkSimulatorApp {
    iosLib = animationIos;
    iosSrc = ../ios;
    name = "hatter-animation-simulator-app";
  };

  filesDirIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/FilesDirDemoMain.hs;
    simulator = true;
  };
  filesDirSimApp = lib.mkSimulatorApp {
    iosLib = filesDirIos;
    iosSrc = ../ios;
    name = "hatter-filesdir-simulator-app";
  };

  textinputRerenderIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/TextInputReRenderDemoMain.hs;
    simulator = true;
  };
  textinputRerenderSimApp = lib.mkSimulatorApp {
    iosLib = textinputRerenderIos;
    iosSrc = ../ios;
    name = "hatter-textinput-rerender-simulator-app";
  };

  stackIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/StackDemoMain.hs;
    simulator = true;
  };
  stackSimApp = lib.mkSimulatorApp {
    iosLib = stackIos;
    iosSrc = ../ios;
    name = "hatter-stack-simulator-app";
  };

  columnChildReorderIos = import ./ios.nix {
    inherit sources;
    mainModule = ../test/ColumnChildReorderDemoMain.hs;
    simulator = true;
  };
  columnChildReorderSimApp = lib.mkSimulatorApp {
    iosLib = columnChildReorderIos;
    iosSrc = ../ios;
    name = "hatter-column-child-reorder-simulator-app";
  };

  xcodegen = pkgs.xcodegen;

  testScripts = builtins.path { path = ../test; name = "test-scripts"; };

in pkgs.stdenv.mkDerivation {
  name = "hatter-simulator-all-tests";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-all-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="me.jappie.hatter"
SCHEME="Hatter"
DEVICE_TYPE="iPhone 16"
COUNTER_SHARE_DIR="${counterSimApp}/share/ios"
SCROLL_SHARE_DIR="${scrollSimApp}/share/ios"
TEXTINPUT_SHARE_DIR="${textinputSimApp}/share/ios"
PERMISSION_SHARE_DIR="${permissionSimApp}/share/ios"
SECURE_STORAGE_SHARE_DIR="${secureStorageSimApp}/share/ios"
IMAGE_SHARE_DIR="${imageSimApp}/share/ios"
NODEPOOL_SHARE_DIR="${nodepoolSimApp}/share/ios"
BLE_SHARE_DIR="${bleSimApp}/share/ios"
DIALOG_SHARE_DIR="${dialogSimApp}/share/ios"
LOCATION_SHARE_DIR="${locationSimApp}/share/ios"
WEBVIEW_SHARE_DIR="${webviewSimApp}/share/ios"
AUTH_SESSION_SHARE_DIR="${authSessionSimApp}/share/ios"
PLATFORM_SIGN_IN_SHARE_DIR="${platformSignInSimApp}/share/ios"
CAMERA_SHARE_DIR="${cameraSimApp}/share/ios"
BOTTOM_SHEET_SHARE_DIR="${bottomSheetSimApp}/share/ios"
HTTP_SHARE_DIR="${httpSimApp}/share/ios"
NETWORK_STATUS_SHARE_DIR="${networkStatusSimApp}/share/ios"
MAPVIEW_SHARE_DIR="${mapviewSimApp}/share/ios"
ANIMATION_SHARE_DIR="${animationSimApp}/share/ios"
FILES_DIR_SHARE_DIR="${filesDirSimApp}/share/ios"
TEXTINPUT_RERENDER_SHARE_DIR="${textinputRerenderSimApp}/share/ios"
STACK_SHARE_DIR="${stackSimApp}/share/ios"
COLUMN_CHILD_REORDER_SHARE_DIR="${columnChildReorderSimApp}/share/ios"
TEST_SCRIPTS="${testScripts}"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/hatter-sim-all-XXXX)
SIM_UDID=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0
PHASE3_OK=0
PHASE4_OK=0
PHASE5_OK=0
PHASE6_OK=0
PHASE7_OK=0
PHASE8_OK=0
PHASE9_OK=0
PHASE10_OK=0
PHASE11_OK=0
PHASE12_OK=0
PHASE13_OK=0
PHASE14_OK=0
PHASE15_OK=0
PHASE16_OK=0
PHASE17_OK=0

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

echo "=== iOS Simulator All-Tests ==="
echo "Working directory: $WORK_DIR"

# --- .a size guard (see docs/ci-ram-regression-110.md) ---
# Fail fast if any test .a exceeds the limit.  Static archives on iOS are
# analogous to .so on Android — bloat here indicates the same whole-archive problem.
A_MAX_MB=120
SIZE_FAIL=0
for share_dir in \
    "$COUNTER_SHARE_DIR" \
    "$SCROLL_SHARE_DIR" \
    "$TEXTINPUT_SHARE_DIR" \
    "$PERMISSION_SHARE_DIR" \
    "$SECURE_STORAGE_SHARE_DIR" \
    "$IMAGE_SHARE_DIR" \
    "$NODEPOOL_SHARE_DIR" \
    "$BLE_SHARE_DIR" \
    "$DIALOG_SHARE_DIR" \
    "$LOCATION_SHARE_DIR" \
    "$WEBVIEW_SHARE_DIR" \
    "$AUTH_SESSION_SHARE_DIR" \
    "$PLATFORM_SIGN_IN_SHARE_DIR" \
    "$CAMERA_SHARE_DIR" \
    "$BOTTOM_SHEET_SHARE_DIR" \
    "$HTTP_SHARE_DIR" \
    "$MAPVIEW_SHARE_DIR" \
    "$TEXTINPUT_RERENDER_SHARE_DIR" \
    "$STACK_SHARE_DIR" \
    "$COLUMN_CHILD_REORDER_SHARE_DIR"; do
    a_path="$share_dir/lib/libHatter.a"
    A_BYTES=$(stat -f %z "$a_path" 2>/dev/null || stat -c %s "$a_path" 2>/dev/null || echo 0)
    A_MB=$((A_BYTES / 1048576))
    A_LABEL=$(echo "$share_dir" | grep -oE '[^/]+/share' | sed 's|/share||')
    if [ "$A_MB" -gt "$A_MAX_MB" ]; then
        echo "FAIL  $A_LABEL .a is ''${A_MB} MB (limit: ''${A_MAX_MB} MB)"
        SIZE_FAIL=1
    else
        echo "OK    $A_LABEL .a is ''${A_MB} MB"
    fi
done
if [ "$SIZE_FAIL" -eq 1 ]; then
    echo ""
    echo "FATAL: .a size limit exceeded. See docs/ci-ram-regression-110.md"
    exit 1
fi
echo ""

# ===========================================================================
# PHASE 0 — Build both apps + boot simulator
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 0: Build apps and boot simulator"
echo "============================================================"

# --- Stage and build counter app ---
echo "=== Staging counter app ==="
mkdir -p "$WORK_DIR/counter/lib" "$WORK_DIR/counter/include"
cp "$COUNTER_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/counter/lib/"
cp "$COUNTER_SHARE_DIR/include/Hatter.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/counter/include/"
cp "$COUNTER_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/counter/include/"
cp -r "$COUNTER_SHARE_DIR/Hatter" "$WORK_DIR/counter/"
cp "$COUNTER_SHARE_DIR/project.yml" "$WORK_DIR/counter/"
chmod -R u+w "$WORK_DIR/counter"

echo "=== Generating counter Xcode project ==="
cd "$WORK_DIR/counter"
${xcodegen}/bin/xcodegen generate

echo "=== Building counter app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/counter-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

COUNTER_APP=$(find "$WORK_DIR/counter-build" -name "*.app" -type d | head -1)
if [ -z "$COUNTER_APP" ]; then
    echo "ERROR: Could not find counter .app bundle"
    exit 1
fi
echo "Counter app: $COUNTER_APP"

# --- Stage and build scroll demo app ---
echo "=== Staging scroll demo app ==="
mkdir -p "$WORK_DIR/scroll/lib" "$WORK_DIR/scroll/include"
cp "$SCROLL_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/scroll/lib/"
cp "$SCROLL_SHARE_DIR/include/Hatter.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/scroll/include/"
cp "$SCROLL_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/scroll/include/"
cp -r "$SCROLL_SHARE_DIR/Hatter" "$WORK_DIR/scroll/"
cp "$SCROLL_SHARE_DIR/project.yml" "$WORK_DIR/scroll/"
chmod -R u+w "$WORK_DIR/scroll"

echo "=== Generating scroll Xcode project ==="
cd "$WORK_DIR/scroll"
${xcodegen}/bin/xcodegen generate

echo "=== Building scroll demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/scroll-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

SCROLL_APP=$(find "$WORK_DIR/scroll-build" -name "*.app" -type d | head -1)
if [ -z "$SCROLL_APP" ]; then
    echo "ERROR: Could not find scroll .app bundle"
    exit 1
fi
echo "Scroll app: $SCROLL_APP"

# --- Stage and build textinput demo app ---
echo "=== Staging textinput demo app ==="
mkdir -p "$WORK_DIR/textinput/lib" "$WORK_DIR/textinput/include"
cp "$TEXTINPUT_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/textinput/lib/"
cp "$TEXTINPUT_SHARE_DIR/include/Hatter.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/textinput/include/"
cp "$TEXTINPUT_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/textinput/include/"
cp -r "$TEXTINPUT_SHARE_DIR/Hatter" "$WORK_DIR/textinput/"
cp "$TEXTINPUT_SHARE_DIR/project.yml" "$WORK_DIR/textinput/"
chmod -R u+w "$WORK_DIR/textinput"

echo "=== Generating textinput Xcode project ==="
cd "$WORK_DIR/textinput"
${xcodegen}/bin/xcodegen generate

echo "=== Building textinput demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/textinput-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

TEXTINPUT_APP=$(find "$WORK_DIR/textinput-build" -name "*.app" -type d | head -1)
if [ -z "$TEXTINPUT_APP" ]; then
    echo "ERROR: Could not find textinput .app bundle"
    exit 1
fi
echo "TextInput app: $TEXTINPUT_APP"

# --- Stage and build permission demo app ---
echo "=== Staging permission demo app ==="
mkdir -p "$WORK_DIR/permission/lib" "$WORK_DIR/permission/include"
cp "$PERMISSION_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/permission/lib/"
cp "$PERMISSION_SHARE_DIR/include/Hatter.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/permission/include/"
cp "$PERMISSION_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/permission/include/"
cp -r "$PERMISSION_SHARE_DIR/Hatter" "$WORK_DIR/permission/"
cp "$PERMISSION_SHARE_DIR/project.yml" "$WORK_DIR/permission/"
chmod -R u+w "$WORK_DIR/permission"

echo "=== Generating permission Xcode project ==="
cd "$WORK_DIR/permission"
${xcodegen}/bin/xcodegen generate

echo "=== Building permission demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/permission-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

PERMISSION_APP=$(find "$WORK_DIR/permission-build" -name "*.app" -type d | head -1)
if [ -z "$PERMISSION_APP" ]; then
    echo "ERROR: Could not find permission .app bundle"
    exit 1
fi
echo "Permission app: $PERMISSION_APP"

# --- Stage and build securestorage demo app ---
echo "=== Staging securestorage demo app ==="
mkdir -p "$WORK_DIR/securestorage/lib" "$WORK_DIR/securestorage/include"
cp "$SECURE_STORAGE_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/securestorage/lib/"
cp "$SECURE_STORAGE_SHARE_DIR/include/Hatter.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/securestorage/include/"
cp "$SECURE_STORAGE_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/securestorage/include/"
cp -r "$SECURE_STORAGE_SHARE_DIR/Hatter" "$WORK_DIR/securestorage/"
cp "$SECURE_STORAGE_SHARE_DIR/project.yml" "$WORK_DIR/securestorage/"
chmod -R u+w "$WORK_DIR/securestorage"

echo "=== Generating securestorage Xcode project ==="
cd "$WORK_DIR/securestorage"
${xcodegen}/bin/xcodegen generate

echo "=== Building securestorage demo app for simulator (ad-hoc signed for Keychain entitlements) ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/securestorage-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

SECURE_STORAGE_APP=$(find "$WORK_DIR/securestorage-build" -name "*.app" -type d | head -1)
if [ -z "$SECURE_STORAGE_APP" ]; then
    echo "ERROR: Could not find securestorage .app bundle"
    exit 1
fi
echo "SecureStorage app: $SECURE_STORAGE_APP"

# --- Stage and build image test app ---
echo "=== Staging image test app ==="
mkdir -p "$WORK_DIR/image/lib" "$WORK_DIR/image/include"
cp "$IMAGE_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/image/lib/"
cp "$IMAGE_SHARE_DIR/include/Hatter.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/image/include/"
cp "$IMAGE_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/image/include/"
cp -r "$IMAGE_SHARE_DIR/Hatter" "$WORK_DIR/image/"
cp "$IMAGE_SHARE_DIR/project.yml" "$WORK_DIR/image/"
chmod -R u+w "$WORK_DIR/image"

echo "=== Generating image Xcode project ==="
cd "$WORK_DIR/image"
${xcodegen}/bin/xcodegen generate

echo "=== Building image test app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/image-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

IMAGE_APP=$(find "$WORK_DIR/image-build" -name "*.app" -type d | head -1)
if [ -z "$IMAGE_APP" ]; then
    echo "ERROR: Could not find image .app bundle"
    exit 1
fi
echo "Image app: $IMAGE_APP"

# --- Stage and build node-pool test app ---
echo "=== Staging node-pool test app ==="
mkdir -p "$WORK_DIR/nodepool/lib" "$WORK_DIR/nodepool/include"
cp "$NODEPOOL_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/nodepool/lib/"
cp "$NODEPOOL_SHARE_DIR/include/Hatter.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/nodepool/include/"
cp "$NODEPOOL_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/nodepool/include/"
cp -r "$NODEPOOL_SHARE_DIR/Hatter" "$WORK_DIR/nodepool/"
cp "$NODEPOOL_SHARE_DIR/project.yml" "$WORK_DIR/nodepool/"
chmod -R u+w "$WORK_DIR/nodepool"

echo "=== Generating node-pool Xcode project ==="
cd "$WORK_DIR/nodepool"
${xcodegen}/bin/xcodegen generate

echo "=== Building node-pool test app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/nodepool-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

NODEPOOL_APP=$(find "$WORK_DIR/nodepool-build" -name "*.app" -type d | head -1)
if [ -z "$NODEPOOL_APP" ]; then
    echo "ERROR: Could not find node-pool .app bundle"
    exit 1
fi
echo "NodePool app: $NODEPOOL_APP"

# --- Stage and build BLE demo app ---
echo "=== Staging BLE demo app ==="
mkdir -p "$WORK_DIR/ble/lib" "$WORK_DIR/ble/include"
cp "$BLE_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/ble/lib/"
cp "$BLE_SHARE_DIR/include/Hatter.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/ble/include/"
cp "$BLE_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/ble/include/"
cp -r "$BLE_SHARE_DIR/Hatter" "$WORK_DIR/ble/"
cp "$BLE_SHARE_DIR/project.yml" "$WORK_DIR/ble/"
chmod -R u+w "$WORK_DIR/ble"

echo "=== Generating BLE Xcode project ==="
cd "$WORK_DIR/ble"
${xcodegen}/bin/xcodegen generate

echo "=== Building BLE demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/ble-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

BLE_APP=$(find "$WORK_DIR/ble-build" -name "*.app" -type d | head -1)
if [ -z "$BLE_APP" ]; then
    echo "ERROR: Could not find BLE .app bundle"
    exit 1
fi
echo "BLE app: $BLE_APP"

# --- Stage and build dialog demo app ---
echo "=== Staging dialog demo app ==="
mkdir -p "$WORK_DIR/dialog/lib" "$WORK_DIR/dialog/include"
cp "$DIALOG_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/dialog/lib/"
cp "$DIALOG_SHARE_DIR/include/Hatter.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/dialog/include/"
cp "$DIALOG_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/dialog/include/"
cp -r "$DIALOG_SHARE_DIR/Hatter" "$WORK_DIR/dialog/"
cp "$DIALOG_SHARE_DIR/project.yml" "$WORK_DIR/dialog/"
chmod -R u+w "$WORK_DIR/dialog"

echo "=== Generating dialog Xcode project ==="
cd "$WORK_DIR/dialog"
${xcodegen}/bin/xcodegen generate

echo "=== Building dialog demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/dialog-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

DIALOG_APP=$(find "$WORK_DIR/dialog-build" -name "*.app" -type d | head -1)
if [ -z "$DIALOG_APP" ]; then
    echo "ERROR: Could not find dialog .app bundle"
    exit 1
fi
echo "Dialog app: $DIALOG_APP"

# --- Stage and build location demo app ---
echo "=== Staging location demo app ==="
mkdir -p "$WORK_DIR/location/lib" "$WORK_DIR/location/include"
cp "$LOCATION_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/location/lib/"
cp "$LOCATION_SHARE_DIR/include/Hatter.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/location/include/"
cp "$LOCATION_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/location/include/"
cp -r "$LOCATION_SHARE_DIR/Hatter" "$WORK_DIR/location/"
cp "$LOCATION_SHARE_DIR/project.yml" "$WORK_DIR/location/"
chmod -R u+w "$WORK_DIR/location"

echo "=== Generating location Xcode project ==="
cd "$WORK_DIR/location"
${xcodegen}/bin/xcodegen generate

echo "=== Building location demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/location-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

LOCATION_APP=$(find "$WORK_DIR/location-build" -name "*.app" -type d | head -1)
if [ -z "$LOCATION_APP" ]; then
    echo "ERROR: Could not find location .app bundle"
    exit 1
fi
echo "Location app: $LOCATION_APP"

# --- Stage and build webview demo app ---
echo "=== Staging webview demo app ==="
mkdir -p "$WORK_DIR/webview/lib" "$WORK_DIR/webview/include"
cp "$WEBVIEW_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/webview/lib/"
cp "$WEBVIEW_SHARE_DIR/include/Hatter.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/webview/include/"
cp "$WEBVIEW_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/webview/include/"
cp -r "$WEBVIEW_SHARE_DIR/Hatter" "$WORK_DIR/webview/"
cp "$WEBVIEW_SHARE_DIR/project.yml" "$WORK_DIR/webview/"
chmod -R u+w "$WORK_DIR/webview"

echo "=== Generating webview Xcode project ==="
cd "$WORK_DIR/webview"
${xcodegen}/bin/xcodegen generate

echo "=== Building webview demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/webview-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

WEBVIEW_APP=$(find "$WORK_DIR/webview-build" -name "*.app" -type d | head -1)
if [ -z "$WEBVIEW_APP" ]; then
    echo "ERROR: Could not find webview .app bundle"
    exit 1
fi
echo "WebView app: $WEBVIEW_APP"

# --- Stage and build authsession demo app ---
echo "=== Staging authsession demo app ==="
mkdir -p "$WORK_DIR/authsession/lib" "$WORK_DIR/authsession/include"
cp "$AUTH_SESSION_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/authsession/lib/"
cp "$AUTH_SESSION_SHARE_DIR/include/Hatter.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/authsession/include/"
cp "$AUTH_SESSION_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/authsession/include/"
cp -r "$AUTH_SESSION_SHARE_DIR/Hatter" "$WORK_DIR/authsession/"
cp "$AUTH_SESSION_SHARE_DIR/project.yml" "$WORK_DIR/authsession/"
chmod -R u+w "$WORK_DIR/authsession"

echo "=== Generating authsession Xcode project ==="
cd "$WORK_DIR/authsession"
${xcodegen}/bin/xcodegen generate

echo "=== Building authsession demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/authsession-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

AUTH_SESSION_APP=$(find "$WORK_DIR/authsession-build" -name "*.app" -type d | head -1)
if [ -z "$AUTH_SESSION_APP" ]; then
    echo "ERROR: Could not find authsession .app bundle"
    exit 1
fi
echo "AuthSession app: $AUTH_SESSION_APP"

# --- Stage and build platformsignin demo app ---
echo "=== Staging platformsignin demo app ==="
mkdir -p "$WORK_DIR/platformsignin/lib" "$WORK_DIR/platformsignin/include"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/platformsignin/lib/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/Hatter.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/platformsignin/include/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/platformsignin/include/"
cp -r "$PLATFORM_SIGN_IN_SHARE_DIR/Hatter" "$WORK_DIR/platformsignin/"
cp "$PLATFORM_SIGN_IN_SHARE_DIR/project.yml" "$WORK_DIR/platformsignin/"
chmod -R u+w "$WORK_DIR/platformsignin"

echo "=== Generating platformsignin Xcode project ==="
cd "$WORK_DIR/platformsignin"
${xcodegen}/bin/xcodegen generate

echo "=== Building platformsignin demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/platformsignin-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

PLATFORM_SIGN_IN_APP=$(find "$WORK_DIR/platformsignin-build" -name "*.app" -type d | head -1)
if [ -z "$PLATFORM_SIGN_IN_APP" ]; then
    echo "ERROR: Could not find platformsignin .app bundle"
    exit 1
fi
echo "PlatformSignIn app: $PLATFORM_SIGN_IN_APP"

# --- Stage and build camera demo app ---
echo "=== Staging camera demo app ==="
mkdir -p "$WORK_DIR/camera/lib" "$WORK_DIR/camera/include"
cp "$CAMERA_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/camera/lib/"
cp "$CAMERA_SHARE_DIR/include/Hatter.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/camera/include/"
cp "$CAMERA_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/camera/include/"
cp -r "$CAMERA_SHARE_DIR/Hatter" "$WORK_DIR/camera/"
cp "$CAMERA_SHARE_DIR/project.yml" "$WORK_DIR/camera/"
chmod -R u+w "$WORK_DIR/camera"

echo "=== Generating camera Xcode project ==="
cd "$WORK_DIR/camera"
${xcodegen}/bin/xcodegen generate

echo "=== Building camera demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/camera-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

CAMERA_APP=$(find "$WORK_DIR/camera-build" -name "*.app" -type d | head -1)
if [ -z "$CAMERA_APP" ]; then
    echo "ERROR: Could not find camera .app bundle"
    exit 1
fi
echo "Camera app: $CAMERA_APP"

# --- Stage and build bottomsheet demo app ---
echo "=== Staging bottomsheet demo app ==="
mkdir -p "$WORK_DIR/bottomsheet/lib" "$WORK_DIR/bottomsheet/include"
cp "$BOTTOM_SHEET_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/bottomsheet/lib/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/Hatter.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/bottomsheet/include/"
cp "$BOTTOM_SHEET_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/bottomsheet/include/"
cp -r "$BOTTOM_SHEET_SHARE_DIR/Hatter" "$WORK_DIR/bottomsheet/"
cp "$BOTTOM_SHEET_SHARE_DIR/project.yml" "$WORK_DIR/bottomsheet/"
chmod -R u+w "$WORK_DIR/bottomsheet"

echo "=== Generating bottomsheet Xcode project ==="
cd "$WORK_DIR/bottomsheet"
${xcodegen}/bin/xcodegen generate

echo "=== Building bottomsheet demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/bottomsheet-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

BOTTOM_SHEET_APP=$(find "$WORK_DIR/bottomsheet-build" -name "*.app" -type d | head -1)
if [ -z "$BOTTOM_SHEET_APP" ]; then
    echo "ERROR: Could not find bottomsheet .app bundle"
    exit 1
fi
echo "BottomSheet app: $BOTTOM_SHEET_APP"

# --- Stage and build http demo app ---
echo "=== Staging http demo app ==="
mkdir -p "$WORK_DIR/http/lib" "$WORK_DIR/http/include"
cp "$HTTP_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/http/lib/"
cp "$HTTP_SHARE_DIR/include/Hatter.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/http/include/"
cp "$HTTP_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/http/include/"
cp -r "$HTTP_SHARE_DIR/Hatter" "$WORK_DIR/http/"
cp "$HTTP_SHARE_DIR/project.yml" "$WORK_DIR/http/"
chmod -R u+w "$WORK_DIR/http"

echo "=== Generating http Xcode project ==="
cd "$WORK_DIR/http"
${xcodegen}/bin/xcodegen generate

echo "=== Building http demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/http-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

HTTP_APP=$(find "$WORK_DIR/http-build" -name "*.app" -type d | head -1)
if [ -z "$HTTP_APP" ]; then
    echo "ERROR: Could not find http .app bundle"
    exit 1
fi
echo "HTTP app: $HTTP_APP"

# --- Stage and build network status demo app ---
echo "=== Staging network status demo app ==="
mkdir -p "$WORK_DIR/networkstatus/lib" "$WORK_DIR/networkstatus/include"
cp "$NETWORK_STATUS_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/networkstatus/lib/"
cp "$NETWORK_STATUS_SHARE_DIR/include/Hatter.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/networkstatus/include/"
cp "$NETWORK_STATUS_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/networkstatus/include/"
cp -r "$NETWORK_STATUS_SHARE_DIR/Hatter" "$WORK_DIR/networkstatus/"
cp "$NETWORK_STATUS_SHARE_DIR/project.yml" "$WORK_DIR/networkstatus/"
chmod -R u+w "$WORK_DIR/networkstatus"

echo "=== Generating network status Xcode project ==="
cd "$WORK_DIR/networkstatus"
${xcodegen}/bin/xcodegen generate

echo "=== Building network status demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/networkstatus-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

NETWORK_STATUS_APP=$(find "$WORK_DIR/networkstatus-build" -name "*.app" -type d | head -1)
if [ -z "$NETWORK_STATUS_APP" ]; then
    echo "ERROR: Could not find network status .app bundle"
    exit 1
fi
echo "Network status app: $NETWORK_STATUS_APP"

# --- Stage and build mapview demo app ---
echo "=== Staging mapview demo app ==="
mkdir -p "$WORK_DIR/mapview/lib" "$WORK_DIR/mapview/include"
cp "$MAPVIEW_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/mapview/lib/"
cp "$MAPVIEW_SHARE_DIR/include/Hatter.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/mapview/include/"
cp "$MAPVIEW_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/mapview/include/"
cp -r "$MAPVIEW_SHARE_DIR/Hatter" "$WORK_DIR/mapview/"
cp "$MAPVIEW_SHARE_DIR/project.yml" "$WORK_DIR/mapview/"
chmod -R u+w "$WORK_DIR/mapview"

echo "=== Generating mapview Xcode project ==="
cd "$WORK_DIR/mapview"
${xcodegen}/bin/xcodegen generate

echo "=== Building mapview demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/mapview-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

MAPVIEW_APP=$(find "$WORK_DIR/mapview-build" -name "*.app" -type d | head -1)
if [ -z "$MAPVIEW_APP" ]; then
    echo "ERROR: Could not find mapview .app bundle"
    exit 1
fi
echo "MapView app: $MAPVIEW_APP"

# --- Stage and build animation demo app ---
echo "=== Staging animation demo app ==="
mkdir -p "$WORK_DIR/animation/lib" "$WORK_DIR/animation/include"
cp "$ANIMATION_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/animation/lib/"
cp "$ANIMATION_SHARE_DIR/include/Hatter.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/animation/include/"
cp "$ANIMATION_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/animation/include/"
cp -r "$ANIMATION_SHARE_DIR/Hatter" "$WORK_DIR/animation/"
cp "$ANIMATION_SHARE_DIR/project.yml" "$WORK_DIR/animation/"
chmod -R u+w "$WORK_DIR/animation"

echo "=== Generating animation Xcode project ==="
cd "$WORK_DIR/animation"
${xcodegen}/bin/xcodegen generate

echo "=== Building animation demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/animation-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

ANIMATION_APP=$(find "$WORK_DIR/animation-build" -name "*.app" -type d | head -1)
if [ -z "$ANIMATION_APP" ]; then
    echo "ERROR: Could not find animation .app bundle"
    exit 1
fi
echo "Animation app: $ANIMATION_APP"

# --- Stage and build filesdir demo app ---
echo "=== Staging filesdir demo app ==="
mkdir -p "$WORK_DIR/filesdir/lib" "$WORK_DIR/filesdir/include"
cp "$FILES_DIR_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/filesdir/lib/"
cp "$FILES_DIR_SHARE_DIR/include/Hatter.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/filesdir/include/"
cp "$FILES_DIR_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/filesdir/include/"
cp -r "$FILES_DIR_SHARE_DIR/Hatter" "$WORK_DIR/filesdir/"
cp "$FILES_DIR_SHARE_DIR/project.yml" "$WORK_DIR/filesdir/"
chmod -R u+w "$WORK_DIR/filesdir"

echo "=== Generating filesdir Xcode project ==="
cd "$WORK_DIR/filesdir"
${xcodegen}/bin/xcodegen generate

echo "=== Building filesdir demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/filesdir-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

FILES_DIR_APP=$(find "$WORK_DIR/filesdir-build" -name "*.app" -type d | head -1)
if [ -z "$FILES_DIR_APP" ]; then
    echo "ERROR: Could not find filesdir .app bundle"
    exit 1
fi
echo "FilesDir app: $FILES_DIR_APP"

# --- Stage and build textinput-rerender demo app ---
echo "=== Staging textinput-rerender demo app ==="
mkdir -p "$WORK_DIR/textinput-rerender/lib" "$WORK_DIR/textinput-rerender/include"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/lib/libHatter.a" "$WORK_DIR/textinput-rerender/lib/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/Hatter.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/UIBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/PermissionBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/SecureStorageBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/BleBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/DialogBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/LocationBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/AuthSessionBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/PlatformSignInBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/CameraBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/BottomSheetBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/HttpBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/NetworkStatusBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/include/AnimationBridge.h" "$WORK_DIR/textinput-rerender/include/"
cp -r "$TEXTINPUT_RERENDER_SHARE_DIR/Hatter" "$WORK_DIR/textinput-rerender/"
cp "$TEXTINPUT_RERENDER_SHARE_DIR/project.yml" "$WORK_DIR/textinput-rerender/"
chmod -R u+w "$WORK_DIR/textinput-rerender"

echo "=== Generating textinput-rerender Xcode project ==="
cd "$WORK_DIR/textinput-rerender"
${xcodegen}/bin/xcodegen generate

echo "=== Building textinput-rerender demo app for simulator ==="
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/textinput-rerender-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

TEXTINPUT_RERENDER_APP=$(find "$WORK_DIR/textinput-rerender-build" -name "*.app" -type d | head -1)
if [ -z "$TEXTINPUT_RERENDER_APP" ]; then
    echo "ERROR: Could not find textinput-rerender .app bundle"
    exit 1
fi
echo "TextInputReRender app: $TEXTINPUT_RERENDER_APP"

echo "=== Building Stack app ==="
cp -r "$STACK_SHARE_DIR" "$WORK_DIR/stack-proj"
chmod -R u+w "$WORK_DIR/stack-proj"
cd "$WORK_DIR/stack-proj"
${xcodegen}/bin/xcodegen generate
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/stack-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

STACK_APP=$(find "$WORK_DIR/stack-build" -name "*.app" -type d | head -1)
if [ -z "$STACK_APP" ]; then
    echo "ERROR: Could not find stack .app bundle"
    exit 1
fi
echo "Stack app: $STACK_APP"

echo "=== Building Column Child Reorder app ==="
cp -r "$COLUMN_CHILD_REORDER_SHARE_DIR" "$WORK_DIR/column-child-reorder-proj"
chmod -R u+w "$WORK_DIR/column-child-reorder-proj"
cd "$WORK_DIR/column-child-reorder-proj"
${xcodegen}/bin/xcodegen generate
xcodebuild build \
    -project Hatter.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/column-child-reorder-build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

COLUMN_CHILD_REORDER_APP=$(find "$WORK_DIR/column-child-reorder-build" -name "*.app" -type d | head -1)
if [ -z "$COLUMN_CHILD_REORDER_APP" ]; then
    echo "ERROR: Could not find column-child-reorder .app bundle"
    exit 1
fi
echo "Column Child Reorder app: $COLUMN_CHILD_REORDER_APP"

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
SIM_UDID=$(xcrun simctl create "test-all-ios" "$DEVICE_TYPE" "$RUNTIME" \
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
STATE="Unknown"
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

# ===========================================================================
# PHASE 1 + PHASE 2 — Run test scripts
# ===========================================================================
export SIM_UDID BUNDLE_ID COUNTER_APP SCROLL_APP TEXTINPUT_APP PERMISSION_APP SECURE_STORAGE_APP IMAGE_APP NODEPOOL_APP BLE_APP DIALOG_APP LOCATION_APP WEBVIEW_APP AUTH_SESSION_APP PLATFORM_SIGN_IN_APP CAMERA_APP BOTTOM_SHEET_APP HTTP_APP NETWORK_STATUS_APP MAPVIEW_APP ANIMATION_APP FILES_DIR_APP TEXTINPUT_RERENDER_APP STACK_APP COLUMN_CHILD_REORDER_APP WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0
PHASE3_EXIT=0
PHASE4_EXIT=0
PHASE5_EXIT=0
PHASE6_EXIT=0
PHASE7_EXIT=0
PHASE8_EXIT=0
PHASE9_EXIT=0
PHASE10_EXIT=0
PHASE11_EXIT=0
PHASE12_EXIT=0
PHASE13_EXIT=0
PHASE14_EXIT=0
PHASE15_EXIT=0
PHASE16_EXIT=0
PHASE17_EXIT=0

# run_with_retry LABEL COMMAND [ARGS...]
# Runs the command up to 10 times. Succeeds on first pass, fails only if all 10 fail.
# If the command outputs "FATAL:", retrying is pointless (e.g. native library failed
# to load), so we stop immediately and report the error.
run_with_retry() {
    local label="$1"; shift
    local max_attempts=10
    local attempt=1
    local output_file="$WORK_DIR/retry_''${label}.log"
    while [ $attempt -le $max_attempts ]; do
        echo "[$label] attempt $attempt/$max_attempts"
        if "$@" 2>&1 | tee "$output_file"; then
            echo "[$label] PASSED on attempt $attempt"
            return 0
        fi
        if grep -q "^FATAL:" "$output_file" 2>/dev/null; then
            echo "[$label] FATAL error detected — not retrying"
            return 1
        fi
        echo "[$label] attempt $attempt FAILED"
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            echo "[$label] retrying in 5s..."
            sleep 5
        fi
    done
    echo "[$label] FAILED after $max_attempts attempts"
    return 1
}

echo ""
echo "--- lifecycle ---"
run_with_retry "lifecycle" bash "$TEST_SCRIPTS/ios/lifecycle.sh" || PHASE1_EXIT=1
echo "--- ui ---"
run_with_retry "ui"        bash "$TEST_SCRIPTS/ios/ui.sh"        || PHASE1_EXIT=1
echo "--- buttons ---"
run_with_retry "buttons"   bash "$TEST_SCRIPTS/ios/buttons.sh"   || PHASE1_EXIT=1
echo "--- scroll ---"
run_with_retry "scroll"    bash "$TEST_SCRIPTS/ios/scroll.sh"    || PHASE2_EXIT=1
echo "--- styled ---"
run_with_retry "styled"    bash "$TEST_SCRIPTS/ios/styled.sh"    || PHASE1_EXIT=1
echo "--- locale ---"
run_with_retry "locale"    bash "$TEST_SCRIPTS/ios/locale.sh"    || PHASE1_EXIT=1
echo "--- textinput ---"
run_with_retry "textinput" bash "$TEST_SCRIPTS/ios/textinput.sh" || PHASE3_EXIT=1
echo "--- permission ---"
run_with_retry "permission" bash "$TEST_SCRIPTS/ios/permission.sh" || PHASE4_EXIT=1
echo "--- securestorage ---"
run_with_retry "securestorage" bash "$TEST_SCRIPTS/ios/securestorage.sh" || PHASE7_EXIT=1
echo "--- image ---"
run_with_retry "image" bash "$TEST_SCRIPTS/ios/image.sh" || PHASE6_EXIT=1
echo "--- node-pool ---"
run_with_retry "node-pool" bash "$TEST_SCRIPTS/ios/node-pool.sh" || PHASE5_EXIT=1
echo "--- ble ---"
run_with_retry "ble" bash "$TEST_SCRIPTS/ios/ble.sh" || PHASE7_EXIT=1
echo "--- dialog ---"
run_with_retry "dialog" bash "$TEST_SCRIPTS/ios/dialog.sh" || PHASE8_EXIT=1
echo "--- location ---"
run_with_retry "location" bash "$TEST_SCRIPTS/ios/location.sh" || PHASE7_EXIT=1
echo "--- webview ---"
run_with_retry "webview" bash "$TEST_SCRIPTS/ios/webview.sh" || PHASE9_EXIT=1
echo "--- mapview ---"
run_with_retry "mapview" bash "$TEST_SCRIPTS/ios/mapview.sh" || PHASE9_EXIT=1
echo "--- authsession ---"
run_with_retry "authsession" bash "$TEST_SCRIPTS/ios/authsession.sh" || PHASE10_EXIT=1
echo "--- platformsignin ---"
run_with_retry "platformsignin" bash "$TEST_SCRIPTS/ios/platformsignin.sh" || PHASE10_EXIT=1
echo "--- camera ---"
run_with_retry "camera" bash "$TEST_SCRIPTS/ios/camera.sh" || PHASE10_EXIT=1
echo "--- bottomsheet ---"
run_with_retry "bottomsheet" bash "$TEST_SCRIPTS/ios/bottomsheet.sh" || PHASE11_EXIT=1
echo "--- http ---"
run_with_retry "http" bash "$TEST_SCRIPTS/ios/http.sh" || PHASE12_EXIT=1
echo "--- networkstatus ---"
run_with_retry "networkstatus" bash "$TEST_SCRIPTS/ios/network_status.sh" || PHASE7_EXIT=1
echo "--- animation ---"
run_with_retry "animation" bash "$TEST_SCRIPTS/ios/animation.sh" || PHASE13_EXIT=1
echo "--- filesdir ---"
run_with_retry "filesdir" bash "$TEST_SCRIPTS/ios/filesdir.sh" || PHASE14_EXIT=1
echo "--- textinput_rerender ---"
run_with_retry "textinput_rerender" bash "$TEST_SCRIPTS/ios/textinput_rerender.sh" || PHASE15_EXIT=1
echo "--- stack ---"
run_with_retry "stack" bash "$TEST_SCRIPTS/ios/stack.sh" || PHASE16_EXIT=1
echo "--- column-child-reorder ---"
run_with_retry "column-child-reorder" bash "$TEST_SCRIPTS/ios/column-child-reorder.sh" || PHASE17_EXIT=1

# --- Phase results ---
if [ $PHASE1_EXIT -eq 0 ]; then
    PHASE1_OK=1
    echo ""
    echo "PHASE 1 PASSED"
else
    echo ""
    echo "PHASE 1 FAILED"
fi

if [ $PHASE2_EXIT -eq 0 ]; then
    PHASE2_OK=1
    echo ""
    echo "PHASE 2 PASSED"
else
    echo ""
    echo "PHASE 2 FAILED"
fi

if [ $PHASE3_EXIT -eq 0 ]; then
    PHASE3_OK=1
    echo ""
    echo "PHASE 3 PASSED"
else
    PHASE3_OK=0
    echo ""
    echo "PHASE 3 FAILED"
fi

if [ $PHASE4_EXIT -eq 0 ]; then
    PHASE4_OK=1
    echo ""
    echo "PHASE 4 PASSED"
else
    PHASE4_OK=0
    echo ""
    echo "PHASE 4 FAILED"
fi

if [ $PHASE5_EXIT -eq 0 ]; then
    PHASE5_OK=1
    echo ""
    echo "PHASE 5 PASSED"
else
    PHASE5_OK=0
    echo ""
    echo "PHASE 5 FAILED"
fi

if [ $PHASE6_EXIT -eq 0 ]; then
    PHASE6_OK=1
    echo ""
    echo "PHASE 6 PASSED"
else
    PHASE6_OK=0
    echo ""
    echo "PHASE 6 FAILED"
fi

if [ $PHASE7_EXIT -eq 0 ]; then
    PHASE7_OK=1
    echo ""
    echo "PHASE 7 PASSED"
else
    PHASE7_OK=0
    echo ""
    echo "PHASE 7 FAILED"
fi

if [ $PHASE8_EXIT -eq 0 ]; then
    PHASE8_OK=1
    echo ""
    echo "PHASE 8 PASSED"
else
    PHASE8_OK=0
    echo ""
    echo "PHASE 8 FAILED"
fi

if [ $PHASE9_EXIT -eq 0 ]; then
    PHASE9_OK=1
    echo ""
    echo "PHASE 9 PASSED"
else
    PHASE9_OK=0
    echo ""
    echo "PHASE 9 FAILED"
fi

if [ $PHASE10_EXIT -eq 0 ]; then
    PHASE10_OK=1
    echo ""
    echo "PHASE 10 PASSED"
else
    PHASE10_OK=0
    echo ""
    echo "PHASE 10 FAILED"
fi

if [ $PHASE11_EXIT -eq 0 ]; then
    PHASE11_OK=1
    echo ""
    echo "PHASE 11 PASSED"
else
    PHASE11_OK=0
    echo ""
    echo "PHASE 11 FAILED"
fi

if [ $PHASE12_EXIT -eq 0 ]; then
    PHASE12_OK=1
    echo ""
    echo "PHASE 12 PASSED"
else
    PHASE12_OK=0
    echo ""
    echo "PHASE 12 FAILED"
fi

if [ $PHASE13_EXIT -eq 0 ]; then
    PHASE13_OK=1
    echo ""
    echo "PHASE 13 PASSED"
else
    PHASE13_OK=0
    echo ""
    echo "PHASE 13 FAILED"
fi

if [ $PHASE14_EXIT -eq 0 ]; then
    PHASE14_OK=1
    echo ""
    echo "PHASE 14 PASSED"
else
    PHASE14_OK=0
    echo ""
    echo "PHASE 14 FAILED"
fi

if [ $PHASE15_EXIT -eq 0 ]; then
    PHASE15_OK=1
    echo ""
    echo "PHASE 15 PASSED"
else
    PHASE15_OK=0
    echo ""
    echo "PHASE 15 FAILED"
fi

if [ $PHASE16_EXIT -eq 0 ]; then
    PHASE16_OK=1
    echo ""
    echo "PHASE 16 PASSED"
else
    PHASE16_OK=0
    echo ""
    echo "PHASE 16 FAILED"
fi

if [ $PHASE17_EXIT -eq 0 ]; then
    PHASE17_OK=1
    echo ""
    echo "PHASE 17 PASSED"
else
    PHASE17_OK=0
    echo ""
    echo "PHASE 17 FAILED"
fi

# ===========================================================================
# Final report
# ===========================================================================
echo ""
echo "============================================================"
echo "FINAL REPORT"
echo "============================================================"

FINAL_EXIT=0

if [ $PHASE1_OK -eq 1 ]; then
    echo "PASS  Phase 1 — Counter app (lifecycle + UI + buttons)"
else
    echo "FAIL  Phase 1 — Counter app (lifecycle + UI + buttons)"
    FINAL_EXIT=1
fi

if [ $PHASE2_OK -eq 1 ]; then
    echo "PASS  Phase 2 — Scroll demo app"
else
    echo "FAIL  Phase 2 — Scroll demo app"
    FINAL_EXIT=1
fi

if [ $PHASE3_OK -eq 1 ]; then
    echo "PASS  Phase 3 — TextInput demo app"
else
    echo "FAIL  Phase 3 — TextInput demo app"
    FINAL_EXIT=1
fi

if [ $PHASE4_OK -eq 1 ]; then
    echo "PASS  Phase 4 — Permission demo app"
else
    echo "FAIL  Phase 4 — Permission demo app"
    FINAL_EXIT=1
fi

if [ $PHASE5_OK -eq 1 ]; then
    echo "PASS  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
else
    echo "FAIL  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
    FINAL_EXIT=1
fi

if [ $PHASE6_OK -eq 1 ]; then
    echo "PASS  Phase 6 — Image demo app"
else
    echo "FAIL  Phase 6 — Image demo app"
    FINAL_EXIT=1
fi

if [ $PHASE7_OK -eq 1 ]; then
    echo "PASS  Phase 7 — SecureStorage + BLE + Location demo app"
else
    echo "FAIL  Phase 7 — SecureStorage + BLE + Location demo app"
    FINAL_EXIT=1
fi

if [ $PHASE8_OK -eq 1 ]; then
    echo "PASS  Phase 8 — Dialog demo app"
else
    echo "FAIL  Phase 8 — Dialog demo app"
    FINAL_EXIT=1
fi

if [ $PHASE9_OK -eq 1 ]; then
    echo "PASS  Phase 9 — WebView demo app"
else
    echo "FAIL  Phase 9 — WebView demo app"
    FINAL_EXIT=1
fi

if [ $PHASE10_OK -eq 1 ]; then
    echo "PASS  Phase 10 — AuthSession demo app"
else
    echo "FAIL  Phase 10 — AuthSession demo app"
    FINAL_EXIT=1
fi

if [ $PHASE11_OK -eq 1 ]; then
    echo "PASS  Phase 11 — BottomSheet demo app"
else
    echo "FAIL  Phase 11 — BottomSheet demo app"
    FINAL_EXIT=1
fi

if [ $PHASE12_OK -eq 1 ]; then
    echo "PASS  Phase 12 — HTTP demo app"
else
    echo "FAIL  Phase 12 — HTTP demo app"
    FINAL_EXIT=1
fi

if [ $PHASE13_OK -eq 1 ]; then
    echo "PASS  Phase 13 — Animation demo app"
else
    echo "FAIL  Phase 13 — Animation demo app"
    FINAL_EXIT=1
fi

if [ $PHASE14_OK -eq 1 ]; then
    echo "PASS  Phase 14 — FilesDir demo app"
else
    echo "FAIL  Phase 14 — FilesDir demo app"
    FINAL_EXIT=1
fi

if [ $PHASE15_OK -eq 1 ]; then
    echo "PASS  Phase 15 — TextInput re-render demo app"
else
    echo "FAIL  Phase 15 — TextInput re-render demo app"
    FINAL_EXIT=1
fi

if [ $PHASE16_OK -eq 1 ]; then
    echo "PASS  Phase 16 — Stack demo app"
else
    echo "FAIL  Phase 16 — Stack demo app"
    FINAL_EXIT=1
fi

if [ $PHASE17_OK -eq 1 ]; then
    echo "PASS  Phase 17 — Column child reorder reproducer"
else
    echo "FAIL  Phase 17 — Column child reorder reproducer"
    FINAL_EXIT=1
fi

echo ""
if [ $FINAL_EXIT -eq 0 ]; then
    echo "All combined simulator integration checks passed!"
else
    echo "Some combined simulator integration checks FAILED."
fi

exit $FINAL_EXIT
SCRIPT

    chmod +x $out/bin/test-all-ios
  '';

  installPhase = "true";
}
