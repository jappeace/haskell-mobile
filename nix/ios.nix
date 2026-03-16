# iOS static library build pipeline.
# Builds Haskell to a single .a using GHC -staticlib, then patches
# Mach-O platform tags from macOS to iOS using mac2ios.
# This is a macOS-only build (same ISA as iOS aarch64).
{ sources ? import ../npins }:
let
  # Use haskell.nix master branch (not armv7a which is Android-specific
  # and has macOS build issues with GHC 8.10.7 patching)
  haskellNix = import sources."haskell.nix-master" {};

  pkgs = import haskellNix.sources.nixpkgs-unstable (haskellNix.nixpkgsArgs // {});

  project = import ./project.nix { inherit pkgs; };

  mac2ios = import ./mac2ios.nix { inherit sources pkgs; };

  nativeLib = project.hsPkgs.haskell-mobile.components.library;

  # Override the library component to produce a rolled-up static archive.
  # GHC -staticlib bundles all Haskell code + RTS + dependencies into one .a.
  # mac2ios then patches LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX to iOS.
  iosLib = nativeLib.override (p: {
    enableShared = false;
    enableStatic = true;

    setupBuildFlags = p.component.setupBuildFlags
      ++ map (x: "--ghc-option=${x}") [
        "-staticlib"
        "-o" "libHaskellMobile.a"
        "-optl-lffi"
      ]
      # Force foreign export symbols to stay — macOS/iOS uses _ prefix
      ++ map (sym: "--ghc-option=-optl-Wl,-u,_${sym}") [
        "haskellInit"
        "haskellGreet"
      ];

    postInstall = ''
      mkdir -p $out/lib $out/include
      ${mac2ios}/bin/mac2ios libHaskellMobile.a
      cp libHaskellMobile.a $out/lib/
      cp ${../include/HaskellMobile.h} $out/include/
    '';
  });

in iosLib
