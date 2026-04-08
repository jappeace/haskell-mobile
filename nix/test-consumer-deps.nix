# Integration test: build an Android library with consumer Hackage deps.
#
# sqlite-simple transitively depends on vector, whose cabal2nix output
# merges internal sub-library deps (tasty, random) into
# libraryHaskellDepends.  This test verifies that resolve-deps.nix
# filters out test frameworks so they don't cause link failures
# (tasty → optparse-applicative → unix/process = undefined symbols).
{ sources ? import ../npins }:
import ./android.nix {
  inherit sources;
  mainModule = ../test/ConsumerDepsMain.hs;
  consumerCabal2Nix =
    { mkDerivation, base, lib, sqlite-simple, text }:
    mkDerivation {
      pname = "consumer-deps-test";
      version = "0.1.0.0";
      libraryHaskellDepends = [ base sqlite-simple text ];
      license = lib.licenses.mit;
    };
}
