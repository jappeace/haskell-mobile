# Produce a patched copy of nixpkgs where compiler-rt recognises "armv7a"
# as a valid ARM32 architecture.  Without this, cmake detects zero supported
# architectures and the compiler-rt build produces an empty output, breaking
# the entire armv7a-android cross-compilation toolchain.
#
# This mirrors the existing X86 precedent already in nixpkgs where i486/i586/
# i686 are added to the X86 set via substituteInPlace + a source alias patch.
#
# When androidArch is not "armv7a", returns the original nixpkgs source as-is.
{ nixpkgsSrc, androidArch }:
if androidArch != "armv7a" then nixpkgsSrc
else
let
  # Import a minimal nixpkgs to get runCommand + python3
  minPkgs = import nixpkgsSrc {};
in
minPkgs.runCommand "nixpkgs-armv7a-patched" {
  nativeBuildInputs = [ minPkgs.python3 ];
} ''
  python3 ${./patch-compiler-rt.py} ${nixpkgsSrc}
''
