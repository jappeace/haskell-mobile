"""Patch nixpkgs for armv7a-android cross-compilation.

Fixes three issues in the nixpkgs source tree:

1. compiler-rt: armv7a not in ARM32 arch set, so cmake detects zero supported
   architectures.  Also, Android baremetal builds can't detect arch because
   -nodefaultlibs prevents check_symbol_exists from linking.

2. compiler-rt: os_version_check.c requires pthread.h, unavailable in baremetal.

3. LLVM package set: llvmPackages.clang for Android uses libcxxClang which
   depends on libcxx.  Building libcxx requires a working cross-linker,
   but the bootstrap clang-wrapper only has GNU binutils (no ld.lld), and
   ld.bfd can't link Android libraries (zstd-compressed debug sections,
   missing builtins path).  Fix: use libstdcxxClang (libcxx=null) for
   Android targets.  GHC's LLVMAS only needs assembly, not C++ support.

Usage: python3 patch-compiler-rt.py <nixpkgs-src-path>
       Writes to $out (set by Nix derivation builder).
"""
import os
import shutil
import stat
import sys

nixpkgs_src = sys.argv[1]
out = os.environ["out"]

shutil.copytree(nixpkgs_src, out, symlinks=True)

target = os.path.join(
    out,
    "pkgs", "development", "compilers", "llvm", "common",
    "compiler-rt", "default.nix",
)

for dirpath, dirnames, filenames in os.walk(os.path.dirname(target)):
    os.chmod(dirpath, os.stat(dirpath).st_mode | stat.S_IWUSR)
    for fn in filenames:
        fp = os.path.join(dirpath, fn)
        os.chmod(fp, os.stat(fp).st_mode | stat.S_IWUSR)

with open(target, "r") as f:
    content = f.read()

# We insert our block between the closing '' of the X86 fix and the next
# + lib.optionalString.  The marker is the unique sequence:
#   ''\n    + lib.optionalString (!haveLibc)
marker = "    ''\n    + lib.optionalString (!haveLibc)"

if marker not in content:
    print("ERROR: Could not find insertion marker in compiler-rt default.nix",
          file=sys.stderr)
    sys.exit(1)

# The armv7a block to insert (raw Nix source code).
# Three fixes:
# 1. Add armv7a to ARM32 set in builtin-config-ix.cmake so builtins are
#    built for this architecture.
# 2. Define armv7a_SOURCES as alias for arm_SOURCES in CMakeLists.txt.
# 3. Fix Android baremetal builds in base-config-ix.cmake:
#    For Android, cmake normally calls detect_target_arch() which uses
#    check_symbol_exists(__arm__).  In baremetal builds, -nodefaultlibs
#    prevents the test from linking, so detection fails and SUPPORTED_ARCH
#    is empty.  We add a COMPILER_RT_DEFAULT_TARGET_ONLY check to use
#    add_default_target_arch() directly (bypassing the broken detection).
#
# Note: in Nix multiline strings (''..''), ''${ prevents interpolation,
# producing literal ${...} in the shell output.  Shell single quotes
# are unrelated to the Nix '' delimiters.
# Use $'...\n...' bash syntax for the base-config-ix.cmake replacement to
# avoid Nix multiline string whitespace stripping, which would eat the
# leading spaces that are significant in the cmake source.
base_find = (
    r"$'    # Examine compiler output to determine target architecture.\n"
    r"    detect_target_arch()'"
)
base_replace = (
    r"$'    # Examine compiler output to determine target architecture.\n"
    r"    if(COMPILER_RT_DEFAULT_TARGET_ONLY)\n"
    r"      add_default_target_arch(''${COMPILER_RT_DEFAULT_TARGET_ARCH})\n"
    r"    else()\n"
    r"      detect_target_arch()\n"
    r"    endif()'"
)
armv7a_block = "\n".join([
    "    ''",
    '    + lib.optionalString (stdenv.hostPlatform.parsed.cpu.name == "armv7a") ' + "''",
    "      substituteInPlace cmake/builtin-config-ix.cmake \\",
    "        --replace-fail 'set(ARM32 arm armhf' 'set(ARM32 armv7a arm armhf'",
    "      substituteInPlace lib/builtins/CMakeLists.txt \\",
    "        --replace-fail 'set(armv7_SOURCES ''${arm_SOURCES})' \\",
    r"        $'set(armv7_SOURCES ''${arm_SOURCES})\nset(armv7a_SOURCES ''${arm_SOURCES})'",
    # os_version_check.c requires pthread.h which doesn't exist in baremetal.
    # Insert a list(REMOVE_ITEM) before the existing baremetal conditional.
    "      substituteInPlace lib/builtins/CMakeLists.txt \\",
    r"        --replace-fail 'if(NOT FUCHSIA AND NOT COMPILER_RT_BAREMETAL_BUILD AND NOT COMPILER_RT_GPU_BUILD)' $'if(COMPILER_RT_BAREMETAL_BUILD)\n  list(REMOVE_ITEM GENERIC_SOURCES os_version_check.c)\nendif()\nif(NOT FUCHSIA AND NOT COMPILER_RT_BAREMETAL_BUILD AND NOT COMPILER_RT_GPU_BUILD)'",
    "      substituteInPlace cmake/base-config-ix.cmake \\",
    "        --replace-fail " + base_find + " \\",
    "        " + base_replace,
    "    ''",
    "    + lib.optionalString (!haveLibc)",
])

content = content.replace(marker, armv7a_block, 1)

with open(target, "w") as f:
    f.write(content)

print("Patched " + target)

# --- Patch 2: LLVM package set ---
# GHC's LLVM backend (required for armv7a, no NCG) depends on
# llvmPackages.clang for LLVMAS.  The default `clang` for non-useLLVM
# non-Darwin targets is `libcxxClang`, which depends on
# targetLlvmPackages.libcxx.  Building libcxx requires the bootstrap
# clang-wrapper with GNU binutils, but ld.bfd can't link Android
# libraries (zstd-compressed debug sections, missing builtins path).
#
# Fix: for Android targets, use libstdcxxClang (which has libcxx=null)
# instead.  GHC only needs clang for assembly (LLVMAS), not C++, so
# the absence of libc++ headers/libraries is fine.
llvm_pkg_set = os.path.join(
    out,
    "pkgs", "development", "compilers", "llvm", "common",
    "default.nix",
)

llvm_dir = os.path.dirname(llvm_pkg_set)
for dirpath, dirnames, filenames in os.walk(llvm_dir):
    os.chmod(dirpath, os.stat(dirpath).st_mode | stat.S_IWUSR)
    for fn in filenames:
        fp = os.path.join(dirpath, fn)
        os.chmod(fp, os.stat(fp).st_mode | stat.S_IWUSR)

with open(llvm_pkg_set, "r") as f:
    llvm_content = f.read()

# The clang selection logic in the LLVM package set:
#   else if stdenv.targetPlatform.useLLVM or false then
#     self.clangUseLLVM
#   else if (targetPackages.stdenv or stdenv).cc.isGNU then
#     self.libstdcxxClang
#   else
#     self.libcxxClang;
#
# We add an Android check before the isGNU/libcxxClang fallback,
# to select libstdcxxClang (no libcxx dependency) for Android.
llvm_marker = (
    "else if (targetPackages.stdenv or stdenv).cc.isGNU then\n"
    "          self.libstdcxxClang"
)

if llvm_marker not in llvm_content:
    print("WARNING: Could not find LLVM clang selection marker, "
          "skipping LLVM package set patch", file=sys.stderr)
else:
    llvm_replacement = (
        "else if stdenv.targetPlatform.isAndroid then\n"
        "          self.libstdcxxClang\n"
        "        else if (targetPackages.stdenv or stdenv).cc.isGNU then\n"
        "          self.libstdcxxClang"
    )
    llvm_content = llvm_content.replace(llvm_marker, llvm_replacement, 1)

    with open(llvm_pkg_set, "w") as f:
        f.write(llvm_content)

    print("Patched " + llvm_pkg_set)

# --- Patch 3: Haskell generic-builder iserv-wrapper profiling ---
# generic-builder.nix always builds both profiled and non-profiled
# iserv-wrapper variants.  For armv7a the cross-GHC is built without
# profiled boot libraries (enableProfiledLibs = false), so the profiled
# iserv-proxy-interpreter can't compile (base .p_hi files missing).
#
# Fix: make iserv-wrapper-both only include the non-profiled wrapper.
generic_builder = os.path.join(
    out,
    "pkgs", "development", "haskell-modules", "generic-builder.nix",
)

gb_dir = os.path.dirname(generic_builder)
for dirpath, dirnames, filenames in os.walk(gb_dir):
    os.chmod(dirpath, os.stat(dirpath).st_mode | stat.S_IWUSR)
    for fn in filenames:
        fp = os.path.join(dirpath, fn)
        os.chmod(fp, os.stat(fp).st_mode | stat.S_IWUSR)

with open(generic_builder, "r") as f:
    gb_content = f.read()

# Replace the paths list that builds both profiled and non-profiled wrappers
# with one that only builds the non-profiled wrapper.
gb_marker = "paths = map wrapperScript [\n            false\n            true\n          ];"
gb_replacement = "paths = map wrapperScript [\n            false\n          ];"

if gb_marker not in gb_content:
    print("WARNING: Could not find iserv-wrapper-both marker in "
          "generic-builder.nix, skipping profiling patch", file=sys.stderr)
else:
    gb_content = gb_content.replace(gb_marker, gb_replacement, 1)
    with open(generic_builder, "w") as f:
        f.write(gb_content)
    print("Patched " + generic_builder)
