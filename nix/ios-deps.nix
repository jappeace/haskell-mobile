# Build Hackage packages with the host GHC for iOS.
#
# iOS builds use the native macOS GHC (not a cross-GHC) — the resulting
# Mach-O is later patched with mac2ios.  Uses nixpkgs haskellPackages
# infrastructure, then collects the results via collect-deps.nix.
#
# Output structure (same as cross-deps.nix):
#   $out/lib/*.a       — static archives
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Consumers supply their own dependencies via consumerCabalFile (IFD),
# consumerCabal2Nix (pre-generated), or hpkgs overrides.
{ sources
, consumerCabalFile ? null
, consumerCabal2Nix ? null
, hpkgs ? (_: _: {})       # consumer haskellPackages overrides
}:
let
  pkgs = import sources.nixpkgs {};

  nativeHaskellPkgs = pkgs.haskellPackages.override {
    overrides = hpkgs;
  };

  ghc = nativeHaskellPkgs.ghc;
  ghcPkgCmd = "${ghc}/bin/ghc-pkg";

  resolvedDeps = import ./resolve-deps.nix {
    inherit pkgs consumerCabalFile consumerCabal2Nix;
    haskellPkgs = nativeHaskellPkgs;
  };

in import ./collect-deps.nix {
  inherit pkgs ghc ghcPkgCmd;
  deps = resolvedDeps;
}
