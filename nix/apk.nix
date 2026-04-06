# APK packaging — thin wrapper around lib.nix.
# Builds a multi-arch APK containing both arm64-v8a and armeabi-v7a.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  sharedLibAarch64 = import ./android.nix { inherit sources; androidArch = "aarch64"; };
  sharedLibArmv7a  = import ./android.nix { inherit sources; androidArch = "armv7a"; };
in
lib.mkApk {
  sharedLibs = [
    { lib = sharedLibAarch64; abiDir = "arm64-v8a"; }
    { lib = sharedLibArmv7a;  abiDir = "armeabi-v7a"; }
  ];
  androidSrc = ../android;
  apkName = "haskell-mobile.apk";
  name = "haskell-mobile-apk";
}
