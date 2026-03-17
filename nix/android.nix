{ sources ? import ../npins }:
let
  # Import haskell.nix from the armv7a branch (provides Android cross-compiler)
  haskellNix = import sources."haskell.nix" {};

  # Use nixpkgs-2305 which has LLVM 14. nixpkgs-unstable has LLVM 19 whose
  # compiler-rt is broken for Android (os_version_check.c needs pthread.h
  # which is unavailable in the builtins-only sysroot).
  # See: https://github.com/NixOS/nixpkgs/issues/380604

  # Android API 26 (Android 8.0 Oreo) overlay — re-imports nixpkgs with
  # modified crossSystem, same approach as simplex-chat.
  android26 = final: prev: {
    pkgsCross = prev.pkgsCross // {
      aarch64-android = import prev.path {
        crossSystem = prev.lib.systems.examples.aarch64-android // {
          sdkVer = "26";
        };
        localSystem = prev.buildPlatform;
        inherit (prev) config overlays;
      };
    };
  };

  pkgs = import haskellNix.sources.nixpkgs-2305 (haskellNix.nixpkgsArgs // {
    overlays = haskellNix.nixpkgsArgs.overlays ++ [ android26 ];
  });

  androidPkgs = pkgs.pkgsCross.aarch64-android;

  # Android doesn't have LANGINFO_CODESET, but nixpkgs autoconf detects it.
  # Patch libiconv to undefine it and enable static linking.
  androidIconv = (androidPkgs.libiconv.override {
    enableStatic = true;
  }).overrideAttrs (old: {
    postConfigure = ''
      echo "#undef HAVE_LANGINFO_CODESET" >> libcharset/config.h
      echo "#undef HAVE_LANGINFO_CODESET" >> lib/config.h
    '';
  });

  # Disable fortify hardening (incompatible with Android NDK) and enable static.
  androidFFI = androidPkgs.libffi.overrideAttrs (old: {
    dontDisableStatic = true;
    hardeningDisable = [ "fortify" ];
  });

  project = import ./project.nix { inherit pkgs; };

in {
  inherit pkgs androidPkgs androidIconv androidFFI;
  lib = project.projectCross.aarch64-android.hsPkgs.haskell-mobile.components.library;
  crossLib = project.projectCross.aarch64-android.hsPkgs.haskell-mobile.components.library;
  # Expose all cross-compiled haskell packages for linking
  hsPkgs = project.projectCross.aarch64-android.hsPkgs;
}
