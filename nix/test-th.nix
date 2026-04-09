# Integration test: build an Android library with a TH-using dependency.
#
# th-consumer is a minimal Haskell package containing a single TH splice.
# If this builds for aarch64-android, TH cross-compilation works:
# iserv-proxy-interpreter runs under QEMU, evaluates TH splices,
# and sends results back to the cross-GHC.
{ sources ? import ../npins }:
import ./android.nix {
  inherit sources;
  mainModule = ../test/THDemoMain.hs;
  hpkgs = self: super: {
    th-consumer = self.callCabal2nix "th-consumer" ../test/th-consumer {};
  };
  consumerCabal2Nix =
    { mkDerivation, base, lib, th-consumer }:
    mkDerivation {
      pname = "th-test";
      version = "0.1.0.0";
      libraryHaskellDepends = [ base th-consumer ];
      license = lib.licenses.mit;
    };
}
