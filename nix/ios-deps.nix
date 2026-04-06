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
# Currently builds: direct-sqlite, prettyprinter.
{ sources }:
let
  pkgs = import sources.nixpkgs {};

  ghc = pkgs.haskellPackages.ghc;
  ghcCmd = "${ghc}/bin/ghc";
  ghcPkgCmd = "${ghc}/bin/ghc-pkg";
  hsc2hsCmd = "${ghc}/bin/hsc2hs";

  # Wrapper cabal project — declares all build-depends.
  # Shared with cross-deps.nix.
  wrapperProject = ./deps-wrapper;
  cabalConfig = ./cabal-config;

  # Fetch source tarballs
  directSqliteSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/direct-sqlite-2.3.29/direct-sqlite-2.3.29.tar.gz";
    sha256 = "1byhnk4jcv83iw7rqw48p8xk6s2dfs1dh6ibwwzkc9m9lwwcwajz";
  };

  prettyprinterSrc = pkgs.fetchurl {
    url = "https://hackage.haskell.org/package/prettyprinter-1.7.1/prettyprinter-1.7.1.tar.gz";
    sha256 = "sha256-Xm6mkDEU+hGPzDWWM9+37N3suSwGyFPQKne3KyUfC0U=";
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

    # --- Unpack source packages ---
    mkdir -p $TMPDIR/deps
    cd $TMPDIR/deps
    tar xzf ${directSqliteSrc}
    tar xzf ${prettyprinterSrc}

    # --- Patch out build-tool-depends ---
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
          $TMPDIR/deps/prettyprinter-1.7.1/

package direct-sqlite
  flags: -systemlib

tests: False
benchmarks: False
EOF

    # --- Build all deps with host GHC ---
    cabal build --offline \
      --with-compiler=${ghcCmd} \
      --with-hc-pkg=${ghcPkgCmd} \
      --with-hsc2hs=${hsc2hsCmd} \
      lib:direct-sqlite lib:prettyprinter
  '';

  installPhase = ''
    DIST=$TMPDIR/project/dist-newstyle/build
    mkdir -p $out/lib $out/hi $out/pkgdb

    # --- Helper: install one package's artifacts ---
    install_pkg() {
      local PKG_NAME=$1
      local BUILD_DIR
      BUILD_DIR=$(find $DIST -path "*/$PKG_NAME-*/build" -type d | head -1 || true)
      if [ ! -d "$BUILD_DIR" ]; then
        echo "ERROR: Could not find $PKG_NAME build directory"
        find $DIST -type d 2>/dev/null | head -30
        exit 1
      fi
      echo "Installing $PKG_NAME from: $BUILD_DIR"

      # Copy static archives
      cp "$BUILD_DIR"/libHS''${PKG_NAME}-*.a $out/lib/ 2>/dev/null || true

      # Copy interface files (preserving directory structure)
      (cd "$BUILD_DIR" && find . -name '*.hi' -exec cp --parents {} $out/hi/ \;) 2>/dev/null || true
    }

    install_pkg direct-sqlite
    install_pkg prettyprinter

    echo "Copied .a files:"
    ls -lh $out/lib/

    echo "Copied .hi files:"
    find $out/hi -name '*.hi'

    # --- Create package database ---
    BASE_ID=$(${ghcPkgCmd} field base id --simple-output 2>/dev/null || echo "base-4.20.0.0")
    BYTESTRING_ID=$(${ghcPkgCmd} field bytestring id --simple-output 2>/dev/null || echo "bytestring-0.12.1.0")
    TEXT_ID=$(${ghcPkgCmd} field text id --simple-output 2>/dev/null || echo "text-2.1.1")
    DEEPSEQ_ID=$(${ghcPkgCmd} field deepseq id --simple-output 2>/dev/null || echo "deepseq-1.5.0.0")

    # --- Helper: extract unit ID from .a filename ---
    get_unit_id() {
      local PKG=$1
      local A_FILE
      A_FILE=$(basename $out/lib/libHS''${PKG}-*.a 2>/dev/null | head -1)
      local UNIT_ID=''${A_FILE#libHS}
      UNIT_ID=''${UNIT_ID%.a}
      echo "$UNIT_ID"
    }

    DS_UNIT_ID=$(get_unit_id direct-sqlite)
    PP_UNIT_ID=$(get_unit_id prettyprinter)

    cat > $out/pkgdb/direct-sqlite.conf << CONF
name: direct-sqlite
version: 2.3.29
id: $DS_UNIT_ID
key: $DS_UNIT_ID
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

    cat > $out/pkgdb/prettyprinter.conf << CONF
name: prettyprinter
version: 1.7.1
id: $PP_UNIT_ID
key: $PP_UNIT_ID
exposed: True
exposed-modules: Prettyprinter Prettyprinter.Internal Prettyprinter.Internal.Type Prettyprinter.Render.String Prettyprinter.Render.Text Prettyprinter.Render.Util.Panic Prettyprinter.Render.Util.SimpleDocTree Prettyprinter.Render.Util.StackMachine Prettyprinter.Symbols.Ascii Prettyprinter.Symbols.Unicode
import-dirs: $out/hi
library-dirs: $out/lib
hs-libraries: HSprettyprinter-1.7.1-inplace
depends:
    $BASE_ID
    $TEXT_ID
    $DEEPSEQ_ID
CONF

    ${ghcPkgCmd} --package-db=$out/pkgdb recache

    echo "Package database:"
    ${ghcPkgCmd} --package-db=$out/pkgdb list
  '';
}
