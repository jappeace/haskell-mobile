{ sources ? import ../npins }:
let
  # Import haskell.nix from the armv7a branch (provides Android cross-compiler)
  haskellNix = import sources."haskell.nix" {};

  # Override aarch64-android to target API level 26 (Android 8.0)
  android26 = final: prev: {
    pkgsCross = prev.pkgsCross // {
      aarch64-android = import prev.path {
        inherit (prev) system overlays;
        crossSystem = prev.lib.systems.examples.aarch64-android // {
          sdkVer = "26";
        };
      };
    };
  };

  # Use haskell.nix's own nixpkgs for better IOHK binary cache hits
  pkgs = import haskellNix.sources.nixpkgs-unstable (haskellNix.nixpkgsArgs // {
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

  project = pkgs.haskell-nix.project {
    compiler-nix-name = "ghc963";
    src = pkgs.haskell-nix.haskellLib.cleanGit {
      name = "haskell-mobile";
      src = ../.;
    };
  };

in {
  inherit androidIconv androidFFI;
  lib = project.projectCross.aarch64-android.hsPkgs.haskell-mobile.components.library;
}
