# Resolve consumer Haskell dependencies.
#
# Given a cabal file (IFD) or pre-generated cabal2nix derivation function,
# resolves the full transitive closure of non-boot Haskell packages using
# nixpkgs haskellPackages.  Returns actual derivations for use with
# collect-deps.nix.
#
# When neither consumerCabalFile nor consumerCabal2Nix is given, returns [].
{ pkgs
, haskellPkgs ? pkgs.haskellPackages
, consumerCabalFile ? null
, consumerCabal2Nix ? null
}:
let
  # Get cabal2nix function: either provided directly or generated via IFD
  cabal2nixFn =
    if consumerCabal2Nix != null then consumerCabal2Nix
    else if consumerCabalFile != null then
      import (pkgs.runCommand "consumer-cabal2nix" {
        nativeBuildInputs = [ pkgs.cabal2nix ];
      } ''
        cabal2nix ${builtins.dirOf consumerCabalFile} > $out
      '')
    else null;

  # Use a spy mkDerivation to extract the dependency list without building.
  # haskellPackages.callPackage passes real packages for each dep name;
  # our fake mkDerivation just captures the attrs cabal2nix produces.
  depInfo =
    if cabal2nixFn != null
    then haskellPkgs.callPackage cabal2nixFn { mkDerivation = attrs: attrs; }
    else { libraryHaskellDepends = []; };

  directDeps = depInfo.libraryHaskellDepends or [];

  # GHC boot/wired-in packages — already provided by the cross-GHC, so they
  # must not be cross-compiled again.  Also excludes haskell-mobile itself
  # (compiled separately in mkAndroidLib/mkIOSLib).
  bootPackageNames = [
    "base" "ghc-prim" "ghc-bignum" "ghc-internal" "integer-gmp"
    "bytestring" "text" "array" "deepseq" "containers"
    "template-haskell" "transformers" "mtl" "stm" "exceptions"
    "filepath" "directory" "process" "unix" "time" "binary"
    "parsec" "pretty" "ghc-boot-th" "ghc-boot" "ghc-heap"
    "hpc" "Cabal" "Cabal-syntax" "os-string"
    "haskell-mobile"
  ];

  isBootPackage = name: builtins.elem name bootPackageNames;

  # Test/benchmark framework packages — never needed at runtime in mobile apps.
  # cabal2nix merges internal sub-library deps into libraryHaskellDepends
  # (e.g. vector's benchmarks-O2 → tasty, random), which leaks these into
  # propagatedBuildInputs.  Their transitive deps (unix, process via
  # optparse-applicative) cause link failures because boot packages aren't
  # linked into the .so.  We exclude them from the transitive walk; consumers
  # who genuinely need these can add them via the hpkgs overlay.
  testFrameworkNames = [
    "tasty" "tasty-bench" "tasty-hunit" "tasty-quickcheck" "tasty-smallcheck"
    "hspec" "hspec-core" "hspec-discover" "hspec-expectations"
    "HUnit"
    "criterion" "gauge"
  ];

  isExcluded = name: isBootPackage name || builtins.elem name testFrameworkNames;

  # Recursively collect all non-boot, non-test-framework Haskell deps from
  # propagatedBuildInputs.
  collectDeps = seen: deps:
    builtins.foldl' (acc: dep:
      let name = dep.pname or "";
      in if name == "" || isExcluded name || builtins.hasAttr name acc
         then acc
         else
           let subDeps = builtins.filter
                 (d: d ? pname && d ? isHaskellLibrary)
                 (dep.propagatedBuildInputs or []);
           in collectDeps (acc // { "${name}" = dep; }) subDeps
    ) seen deps;

  nonBootDirect = builtins.filter
    (d: d ? pname && !(isBootPackage d.pname))
    directDeps;

  allDeps = collectDeps {} nonBootDirect;

in builtins.attrValues allDeps
