# APK packaging — thin wrapper around lib.nix.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  sharedLib = import ./android.nix { inherit sources; };
in
lib.mkApk {
  inherit sharedLib;
  androidSrc = ../android;
  apkName = "haskell-mobile.apk";
  name = "haskell-mobile-apk";
}
