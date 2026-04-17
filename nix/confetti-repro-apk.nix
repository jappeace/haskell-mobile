# Standalone APK for the confetti animation reproducer.
# Usage:
#   nix-build nix/confetti-repro-apk.nix                    # aarch64 (phone)
#   nix-build nix/confetti-repro-apk.nix --argstr androidArch armv7a  # Wear OS
{ sources ? import ../npins, androidArch ? "aarch64" }:
let
  abiDir = { aarch64 = "arm64-v8a"; armv7a = "armeabi-v7a"; }.${androidArch};
  lib = import ./lib.nix { inherit sources androidArch; };
  sharedLib = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/ConfettiRepDemoMain.hs;
  };
in
lib.mkApk {
  sharedLibs = [{ lib = sharedLib; inherit abiDir; }];
  androidSrc = ../android;
  apkName = "hatter-confetti-repro.apk";
  name = "hatter-confetti-repro-apk";
}
