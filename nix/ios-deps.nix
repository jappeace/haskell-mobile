# Build Hackage packages with the host GHC for iOS.
#
# iOS builds use the native macOS GHC (not a cross-GHC) — the resulting
# Mach-O is later patched with mac2ios.  This means we can build Hackage
# deps the simple way: just run cabal with the host compiler.
#
# Output structure (same as cross-deps.nix):
#   $out/lib/*.a       — static archives
#   $out/hi/           — interface files (.hi)
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Currently builds: direct-sqlite (bundled sqlite3.c, no systemlib).
{ sources }:
let
  pkgs = import sources.nixpkgs {};

  ghc = pkgs.haskellPackages.ghc;
  ghcCmd = "${ghc}/bin/ghc";
  ghcPkgCmd = "${ghc}/bin/ghc-pkg";
  hsc2hsCmd = "${ghc}/bin/hsc2hs";

  # Wrapper cabal project — just declares `build-depends: direct-sqlite`
  # so cabal resolves it as a local package.  Shared with cross-deps.nix.
  wrapperProject = ./deps-wrapper;
  cabalConfig = ./cabal-config;

  # Fetch direct-sqlite source tarball
  directSqliteSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/direct-sqlite-2.3.29/direct-sqlite-2.3.29.tar.gz";
    sha256 = "1byhnk4jcv83iw7rqw48p8xk6s2dfs1dh6ibwwzkc9m9lwwcwajz";
  };

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-ios-deps";

  dontUnpack = true;

  nativeBuildInputs = [ ghc pkgs.cabal-install ];

  buildPhase = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME

    # --- Pre-create cabal config to prevent network access ---
    mkdir -p $HOME/.config/cabal
    cp ${cabalConfig} $HOME/.config/cabal/config

    # Create an empty package index so cabal doesn't try to download one.
    mkdir -p $HOME/.local/state/cabal/repo/hackage.haskell.org
    tar cf $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar --files-from /dev/null
    cp $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar \
       $HOME/.local/state/cabal/repo/hackage.haskell.org/01-index.tar.idx 2>/dev/null || true

    # --- Unpack direct-sqlite ---
    mkdir -p $TMPDIR/deps
    cd $TMPDIR/deps
    tar xzf ${directSqliteSrc}

    # --- Patch out build-tool-depends: hsc2hs ---
    # Cabal tries to build hsc2hs from the empty index, failing with
    # --offline.  The host GHC's hsc2hs is already available via --with-hsc2hs.
    sed -i 's/^  build-tool-depends:.*hsc2hs.*/  -- &/' \
      direct-sqlite-2.3.29/direct-sqlite.cabal

    if grep -q '^  build-tool-depends:.*hsc2hs' direct-sqlite-2.3.29/direct-sqlite.cabal; then
      echo "ERROR: Failed to patch out hsc2hs build-tool-depends"
      exit 1
    fi

    # --- Create a wrapper cabal project ---
    cp -r ${wrapperProject} $TMPDIR/project
    chmod -R u+w $TMPDIR/project
    cd $TMPDIR/project

    cat > cabal.project << EOF
packages: .
          $TMPDIR/deps/direct-sqlite-2.3.29/

package direct-sqlite
  flags: -systemlib

tests: False
benchmarks: False
EOF

    # --- Build direct-sqlite with host GHC ---
    cabal build --offline \
      --with-compiler=${ghcCmd} \
      --with-hc-pkg=${ghcPkgCmd} \
      --with-hsc2hs=${hsc2hsCmd} \
      lib:direct-sqlite
  '';

  installPhase = ''
    # --- Locate build artifacts ---
    # Host builds use the host platform triple (e.g. x86_64-osx or aarch64-osx)
    BUILD_DIR=$(find $TMPDIR/project/dist-newstyle/build -path '*/direct-sqlite-*/build' -type d | head -1)
    if [ ! -d "$BUILD_DIR" ]; then
      echo "ERROR: Could not find direct-sqlite build directory"
      echo "dist-newstyle contents:"
      find $TMPDIR/project/dist-newstyle -type d 2>/dev/null | head -30
      exit 1
    fi
    echo "Build directory: $BUILD_DIR"

    # --- Copy static archive ---
    mkdir -p $out/lib
    cp "$BUILD_DIR"/libHSdirect-sqlite-*.a $out/lib/
    echo "Copied .a:"
    ls -lh $out/lib/

    # --- Copy interface files (preserving directory structure) ---
    mkdir -p $out/hi
    (cd "$BUILD_DIR" && find Database -name '*.hi' -exec cp --parents {} $out/hi/ \;)
    echo "Copied .hi files:"
    find $out/hi -name '*.hi'

    # --- Create package database ---
    mkdir -p $out/pkgdb

    A_FILE=$(basename $out/lib/libHS*.a)
    # libHSdirect-sqlite-2.3.29-inplace.a → direct-sqlite-2.3.29-inplace
    UNIT_ID=''${A_FILE#libHS}
    UNIT_ID=''${UNIT_ID%.a}

    BASE_ID=$(${ghcPkgCmd} field base id --simple-output 2>/dev/null || echo "base-4.20.0.0")
    BYTESTRING_ID=$(${ghcPkgCmd} field bytestring id --simple-output 2>/dev/null || echo "bytestring-0.12.1.0")
    TEXT_ID=$(${ghcPkgCmd} field text id --simple-output 2>/dev/null || echo "text-2.1.1")

    cat > $out/pkgdb/direct-sqlite.conf << CONF
name: direct-sqlite
version: 2.3.29
id: $UNIT_ID
key: $UNIT_ID
exposed: True
exposed-modules: Database.SQLite3 Database.SQLite3.Bindings Database.SQLite3.Bindings.Types Database.SQLite3.Direct
import-dirs: $out/hi
library-dirs: $out/lib
hs-libraries: HSdirect-sqlite-2.3.29-inplace
depends:
    $BASE_ID
    $BYTESTRING_ID
    $TEXT_ID
CONF

    ${ghcPkgCmd} --package-db=$out/pkgdb recache

    echo "Package database:"
    ${ghcPkgCmd} --package-db=$out/pkgdb list
  '';
}
