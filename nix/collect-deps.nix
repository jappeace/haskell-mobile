# Collect pre-built Haskell package outputs into a single directory.
#
# Takes a list of nixpkgs haskellPackages derivations (already resolved
# transitively by resolve-deps.nix) and collects their .conf / .a files:
#   $out/lib/*.a       — static archives
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Also collects boot package .a files from the GHC, since consumer deps
# may reference boot packages (os-string, mtl, etc.) that mkAndroidLib
# doesn't whole-archive by default.
{ pkgs
, ghc               # GHC derivation (for boot package .a files)
, ghcPkgCmd         # full path to ghc-pkg (or cross ghc-pkg)
, deps              # list of haskellPackages derivations (from resolve-deps.nix)
}:
let
  depsList = builtins.concatStringsSep " " (map toString deps);

in pkgs.runCommand "haskell-mobile-collected-deps" {
  nativeBuildInputs = [ pkgs.findutils ];
} ''
  mkdir -p $out/lib $out/pkgdb

  for pkg in ${depsList}; do
    echo "Processing: $pkg"

    # Copy .conf files, skipping benchmark/test sub-libraries
    for conf in $(find "$pkg" -name "*.conf" -path "*/package.conf.d/*"); do
      LIB_NAME=$(grep '^lib-name:' "$conf" | sed 's/^lib-name: *//' || true)
      case "$LIB_NAME" in
        *benchmark*|*test*) echo "  skip sub-lib: $LIB_NAME"; continue ;;
      esac
      cp "$conf" $out/pkgdb/
    done

    # Copy all non-profiling .a files from this package, skipping
    # benchmark/test sub-library archives (they reference test frameworks
    # like tasty that aren't available on mobile).
    # We collect all .a files rather than just those in hs-libraries because
    # internal sub-libraries (e.g. attoparsec-internal) have empty
    # hs-libraries fields in their .conf but still need their .a collected.
    find "$pkg" -name 'libHS*.a' ! -name '*_p.a' | while read aFile; do
      aName=$(basename "$aFile")
      case "$aName" in
        *-benchmark*|*-benchmarks*|*-test*) echo "  skip .a: $aName"; continue ;;
      esac
      if [ ! -f "$out/lib/$aName" ]; then
        cp "$aFile" $out/lib/
      fi
    done
  done

  # Collect boot package .a files from the GHC.  Consumer deps may
  # reference boot packages (os-string, mtl, stm, etc.) that mkAndroidLib
  # doesn't whole-archive.  Including them here ensures the linker can
  # resolve all symbols.
  echo "=== Collecting boot package libraries ==="
  find ${ghc}/lib -name 'libHS*.a' ! -name '*_p.a' ! -name '*_thr*' ! -name '*-ghc*' | while read aFile; do
    aName=$(basename "$aFile")
    if [ ! -f "$out/lib/$aName" ]; then
      echo "  boot: $aName"
      cp "$aFile" $out/lib/
    fi
  done

  ${ghcPkgCmd} --package-db=$out/pkgdb recache

  echo "=== Package database ==="
  ${ghcPkgCmd} --package-db=$out/pkgdb list

  echo "=== Libraries ==="
  ls -lh $out/lib/
''
