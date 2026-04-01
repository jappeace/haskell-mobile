# Android emulator SQLite test — verifies database write/read on device.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  crossDeps = import ./cross-deps.nix { inherit sources; };

  androidLib = lib.mkAndroidLib {
    haskellMobileSrc = ../.;
    mainModule = ../test/DbTestMain.hs;
    pname = "haskell-mobile-android-db-test";
    inherit crossDeps;
  };

  apk = lib.mkApk {
    sharedLib = androidLib;
    androidSrc = ../android;
    apkName = "haskell-mobile-db-test.apk";
    name = "haskell-mobile-db-test-apk";
  };
in
lib.mkEmulatorTest {
  inherit apk;
  apkFileName = "haskell-mobile-db-test.apk";
  packageName = "me.jappie.haskellmobile";
  events = [ "Lifecycle: Create" "SQLite roundtrip OK" ];
  name = "haskell-mobile-emulator-db-test";
}
