# Android shared library — thin wrapper around lib.nix.
{ sources ? import ../npins
, androidArch ? "aarch64"
, mainModule ? ../test/ScrollDemoMain.hs
, consumerCabalFile ? null
, consumerCabal2Nix ? null
, hpkgs ? (_: _: {})       # consumer haskellPackages overrides
, maxNodes ? 256            # static pool size (ignored when dynamicNodePool=true)
, dynamicNodePool ? false   # use malloc/realloc instead of fixed array
}:
let
  lib = import ./lib.nix { inherit sources androidArch; };
  crossDeps = import ./cross-deps.nix {
    inherit sources androidArch consumerCabalFile consumerCabal2Nix hpkgs;
  };
  # Pre-compile hatter library objects once.  Nix caches the result by
  # (hatterSrc, androidArch), so all apps sharing the same hatter source
  # reuse the same compilation — no per-app redundant GHC work.
  hatterObjs = lib.mkHatterObjs { hatterSrc = ../.; };
in
lib.mkAndroidLib {
  hatterSrc = ../.;
  inherit mainModule crossDeps maxNodes dynamicNodePool hatterObjs;
}
