# Standalone APK for the EaseIn translate animation demo.
# Usage:
#   nix-build nix/ease-in-translate-apk.nix                    # aarch64 (phone)
#   nix-build nix/ease-in-translate-apk.nix --argstr androidArch armv7a  # Wear OS
{ sources ? import ../npins, androidArch ? "aarch64" }:
let
  abiDir = { aarch64 = "arm64-v8a"; armv7a = "armeabi-v7a"; }.${androidArch};
  lib = import ./lib.nix { inherit sources androidArch; };
  sharedLib = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/EaseInTranslateDemoMain.hs;
  };
in
lib.mkApk {
  sharedLibs = [{ lib = sharedLib; inherit abiDir; }];
  androidSrc = ../android;
  apkName = "hatter-ease-in-translate.apk";
  name = "hatter-ease-in-translate-apk";
}
