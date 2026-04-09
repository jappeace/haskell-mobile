# Fixing Template Haskell Cross-Compilation for Android

## Problem

When cross-compiling Haskell for aarch64-android, Template Haskell splices
are evaluated by running `iserv-proxy-interpreter` (an aarch64 binary) under
QEMU user-mode on the x86_64 build host. This fails with an assertion in
`rts/linker/elf_reloc_aarch64.c:118`:

```
CHECK(isInt64(21+12, addend))
```

The assertion checks that ADRP relocations (between loaded `.o` code and its
GOT) stay within ±4 GiB. Under QEMU, they don't.

## Root Cause

GHC 9.10.3 on aarch64 sets `DEFAULT_LINKER_ALWAYS_PIC = true`
(`rts/include/rts/Flags.h`). This makes `mmapForLinker`
(`rts/linker/MMap.c`) call `mmap(NULL, ...)` — no address hint at all —
bypassing `nearImage()` and `LINKER_LOAD_BASE` entirely.

Under QEMU user-mode, NULL-hint mmaps land at `0x7fb...` (QEMU's top-down
guest allocator), while the static binary sits at `0x200000`. The gap far
exceeds ±4 GiB.

There is no RTS flag to disable `linkerAlwaysPic` on aarch64. The `-xm` flag
only works when `linkerAlwaysPic` is false. The `-xp` flag sets it to true
(already the default).

Both code sections (via M32 allocator, `rts/linker/M32Alloc.c`) and GOT
entries (via `makeGot` in `rts/linker/elf_got.c`) go through
`mmapAnonForLinker` → `mmap(NULL, ...)`, so both end up far from the binary.

## Solution

Five components, all configured in the consumer's `nix/android.nix`. The
consumer passes a modified `sources` (with QEMU overlay) and an `hpkgs`
overlay (with iserv-proxy overrides and mkDerivation patching) to
haskell-mobile's `cross-deps.nix`.

### 1. Static iserv-proxy-interpreter

Link iserv-proxy-interpreter as a static PIE binary so QEMU can run it
without Android's `/system/bin/linker64`:

```nix
iserv-proxy = pkgs.haskell.lib.appendConfigureFlags super.iserv-proxy [
  "--ghc-option=-optl-static"
  "--ghc-option=-optl-pie"
  # ... other flags below
];
```

This requires static versions of C libraries that iserv-proxy depends on:

```nix
gmpStatic = androidPkgs.gmp.overrideAttrs (old: {
  dontDisableStatic = true;
});
libffiStatic = androidPkgs.libffi.overrideAttrs (old: {
  dontDisableStatic = true;
});
numactlStatic = androidPkgs.numactl.overrideAttrs (old: {
  dontDisableStatic = true;
});
```

### 2. Native `libdl.a`

Android NDK ships `libdl.a` as LLVM bitcode (not native ELF) with stub
implementations where `dlerror()` returns "libdl.a is a stub". GHC's RTS
linker can't parse LLVM bitcode.

Replace it with a native-ELF `libdl.a` that implements `dlsym` by walking
the binary's `.dynsym` table. This requires two companion linker flags on
iserv-proxy:

- `--export-dynamic`: populates `.dynsym` with all symbols
- `--hash-style=sysv`: provides `DT_HASH` (our dlsym reads `nchain` from it
  to know the symbol count)

Full C implementation (`dl_impl.c`):

```c
#include <stddef.h>
#include <string.h>
#include <elf.h>
#include <stdint.h>

/* _DYNAMIC is provided by the linker when --export-dynamic is used. */
extern Elf64_Dyn _DYNAMIC[] __attribute__((weak));

static Elf64_Sym  *g_symtab  = NULL;
static const char *g_strtab  = NULL;
static uint32_t    g_nsyms   = 0;
static int         g_inited  = 0;

static void init_symtab(void) {
    Elf64_Dyn *d;
    g_inited = 1;
    if (!_DYNAMIC) return;
    for (d = _DYNAMIC; d->d_tag != DT_NULL; d++) {
        switch (d->d_tag) {
        case DT_SYMTAB:
            g_symtab = (Elf64_Sym *)(uintptr_t)d->d_un.d_ptr;
            break;
        case DT_STRTAB:
            g_strtab = (const char *)(uintptr_t)d->d_un.d_ptr;
            break;
        case DT_HASH: {
            /* SysV hash: uint32_t nbuckets, nchain.
             * nchain == total symbols in .dynsym. */
            uint32_t *h = (uint32_t *)(uintptr_t)d->d_un.d_ptr;
            g_nsyms = h[1];
            break;
        }
        }
    }
}

void *dlopen(const char *filename, int flags) {
    (void)filename; (void)flags;
    return (void *)(uintptr_t)1;  /* fake non-NULL handle */
}

char *dlerror(void) { return NULL; }

void *dlsym(void *handle, const char *symbol) {
    uint32_t i;
    (void)handle;
    if (!g_inited) init_symtab();
    if (!g_symtab || !g_strtab || g_nsyms == 0) return NULL;
    for (i = 0; i < g_nsyms; i++) {
        if (g_symtab[i].st_shndx != SHN_UNDEF &&
            g_symtab[i].st_name  != 0 &&
            strcmp(g_strtab + g_symtab[i].st_name, symbol) == 0) {
            return (void *)(uintptr_t)g_symtab[i].st_value;
        }
    }
    return NULL;
}

int dlclose(void *handle) { (void)handle; return 0; }

void *dlvsym(void *handle, const char *s, const char *v) {
    (void)v;
    return dlsym(handle, s);
}

int dladdr(const void *addr, void *info) {
    (void)addr; (void)info;
    return 0;
}
```

### 3. mmap wrapper (`--wrap=mmap`) — the key fix

This is what actually solves the ADRP relocation assertion. The linker's
`--wrap=mmap` flag redirects all `mmap` calls to `__wrap_mmap`, making the
original available as `__real_mmap`.

The wrapper intercepts `mmap(NULL, ...)` (anonymous, non-fixed) and provides
a hint address starting 2 MiB above the binary's `_end` symbol. QEMU honours
hints when the guest address is free, keeping allocations within ±4 GiB of
the binary.

Full C implementation (`mmap_wrapper.c`):

```c
#include <stddef.h>
#include <stdint.h>

/* Flags from linux/mman.h — same on all architectures */
#define _MAP_ANONYMOUS 0x20
#define _MAP_FIXED     0x10

void *__real_mmap(void *addr, unsigned long length, int prot,
                  int flags, int fd, long offset);

/* _end is provided by the linker: end of BSS = end of binary */
extern char _end;

static void *_mmap_next_hint = 0;

void *__wrap_mmap(void *addr, unsigned long length, int prot,
                  int flags, int fd, long offset) {
    /* Only intercept NULL-hint anonymous mappings */
    if (addr == 0 && (flags & _MAP_ANONYMOUS)
                  && !(flags & _MAP_FIXED)) {
        if (_mmap_next_hint == 0) {
            /* First call: start 2 MiB above end of binary */
            uintptr_t binary_end = ((uintptr_t)&_end + 0xfff)
                                   & ~(uintptr_t)0xfff;
            _mmap_next_hint = (void *)(binary_end + 0x200000);
        }
        void *result = __real_mmap(_mmap_next_hint, length, prot,
                                   flags, fd, offset);
        if (result != (void *)(intptr_t)-1) {
            /* Advance hint past this allocation (page-aligned) */
            uintptr_t next = ((uintptr_t)result + length + 0xfff)
                             & ~(uintptr_t)0xfff;
            _mmap_next_hint = (void *)next;
            return result;
        }
        /* Hint rejected (region occupied): fall through */
    }
    return __real_mmap(addr, length, prot, flags, fd, offset);
}
```

Both C files are compiled into static libraries using the Android NDK cross
compiler and linked into iserv-proxy:

```nix
libdlNative = pkgs.runCommand "libdl-native-android" {
  nativeBuildInputs = [ androidPkgs.stdenv.cc ];
} ''
  cat > dl_impl.c <<'EOF'
  ... (dl_impl.c contents above)
  EOF

  cat > mmap_wrapper.c <<'MEOF'
  ... (mmap_wrapper.c contents above)
  MEOF

  aarch64-unknown-linux-android-clang -c -fPIC -o dl_impl.o dl_impl.c
  aarch64-unknown-linux-android-clang -c -fPIC -o mmap_wrapper.o mmap_wrapper.c
  mkdir -p $out/lib
  aarch64-unknown-linux-android-ar rcs $out/lib/libdl.a dl_impl.o
  aarch64-unknown-linux-android-ar rcs $out/lib/libmmap_wrapper.a mmap_wrapper.o
'';
```

### 4. Package DB patching

GHC's cross-compiler has a global package DB with boot packages (rts, base,
ghc-prim, etc.) that use `${pkgroot}` relative paths and list
`dynamic-library-dirs`. During TH evaluation, the RTS linker tries to load
packages via `LoadDLL` (dynamic) first; on Android there are no `.so` files
for boot packages, so this fails.

The fix: override `mkDerivation` in the hpkgs overlay to add a
`preConfigure` hook that:

1. Copies global package confs into the local package DB (so we can patch them)
2. Resolves `${pkgroot}` to absolute paths (relative refs break when copied)
3. Clears `dynamic-library-dirs` (forces `LoadArchive` — loading `.a` files)
4. Recaches the package DB

The iserv-proxy package itself is excluded from patching — it needs the
unpatched database for its own static linking.

```nix
mkDerivation = args:
  let isIservProxy = (args.pname or "") == "iserv-proxy";
  in super.mkDerivation (args // {
    preConfigure = (args.preConfigure or "") +
      (if isIservProxy then "" else ''
        _ghcLibDir=$(${self.ghc}/bin/${self.ghc.targetPrefix}ghc --print-libdir)
        _globalConfDir="$_ghcLibDir/package.conf.d"
        if [ -d "$_globalConfDir" ] && [ -d "$packageConfDir" ]; then
          echo "TH-fix: copying global package DB from $_globalConfDir"
          for _conf in "$_globalConfDir"/*.conf; do
            _name=$(basename "$_conf")
            if [ ! -e "$packageConfDir/$_name" ]; then
              cp "$_conf" "$packageConfDir/$_name"
            fi
          done
          for _conf in "$packageConfDir"/*.conf; do
            ${pkgs.gawk}/bin/awk -v pkgroot="$_ghcLibDir" '
              { gsub(/\$\{pkgroot\}/, pkgroot) }
              /^dynamic-library-dirs:/ { print "dynamic-library-dirs:"; skip=1; next }
              skip && /^[[:space:]]/ { next }
              { skip=0; print }
            ' "$_conf" > "$_conf.tmp" && mv "$_conf.tmp" "$_conf"
          done
          echo "TH-fix: patched package DB, recaching"
          ${self.ghc}/bin/${self.ghc.targetPrefix}ghc-pkg \
            --package-db="$packageConfDir" recache
        fi
      '');
  });
```

### 5. QEMU `-B 0x4000000000` (guest_base shift)

A thin nixpkgs wrapper (`nix/nixpkgs-qemu-fix/default.nix`) adds an overlay
that wraps `qemu-aarch64` with `-B 0x4000000000`, shifting the guest address
space by 256 GiB. This places the guest binary at an unoccupied host address
so the mmap hints from component 3 are more likely to succeed.

```nix
# nix/nixpkgs-qemu-fix/default.nix
args@{ overlays ? [], ... }:
let
  realNixpkgs = (import ../../npins).nixpkgs;
in
import realNixpkgs (args // {
  overlays = overlays ++ [
    (final: prev: {
      qemu-user = prev.symlinkJoin {
        name = "qemu-user-with-guest-base";
        paths = [ prev.qemu-user ];
        postBuild = ''
          rm $out/bin/qemu-aarch64
          cat > $out/bin/qemu-aarch64 <<'WRAPPER'
#!/bin/sh
exec ${prev.qemu-user}/bin/qemu-aarch64 -B 0x4000000000 "$@"
WRAPPER
          chmod +x $out/bin/qemu-aarch64
        '';
      };
    })
  ];
})
```

The consumer passes this modified nixpkgs to `cross-deps.nix`:

```nix
sourcesWithQemuFix = sources // { nixpkgs = ./nixpkgs-qemu-fix; };

crossDeps = import "${haskellMobileSrc}/nix/cross-deps.nix" {
  sources = sourcesWithQemuFix;
  inherit androidArch consumerCabal2Nix;
  hpkgs = self: super: { ... };
};
```

Note: `-B` alone does NOT fix the issue. It shifts host address mapping but
doesn't change the guest mmap allocator's top-down behaviour. It's
complementary to the `--wrap=mmap` fix in component 3.

## Complete iserv-proxy flags

All the flags together on the iserv-proxy override:

```nix
iserv-proxy = pkgs.haskell.lib.appendConfigureFlags super.iserv-proxy [
  "--ghc-option=-optl-static"            # static binary
  "--ghc-option=-optl-pie"               # position-independent
  "--ghc-option=-optl-Wl,--export-dynamic"  # populate .dynsym
  "--ghc-option=-optl-Wl,--hash-style=sysv" # DT_HASH for dlsym
  "--ghc-option=-optl-Wl,--wrap=mmap"    # mmap interception
  "--ghc-option=-optl-lmmap_wrapper"     # link mmap wrapper lib
  "--extra-lib-dirs=${gmpStatic}/lib"
  "--extra-lib-dirs=${libffiStatic}/lib"
  "--extra-lib-dirs=${numactlStatic}/lib"
  "--extra-lib-dirs=${libdlNative}/lib"   # native libdl + libmmap_wrapper
];
```

## Approaches that were tried and failed

### QEMU `-B` flag alone
Shifts host address mapping (guest_base) but guest mmap allocator still uses
top-down allocation from high addresses. Guest strace confirmed: mmap returns
`0x7fb...` regardless of `-B` value.

### QEMU `-R` flag (reserved_va)
- `-R 2GB`: RTS heap allocation (268MB) fails with ENOMEM
- `-R 4GB`: Scudo (Android's allocator) ERROR requesting 8.4TB for its
  secondary allocator
- `-R 32GB`: Allocations succeed but at ~11.5GB from binary (top-down
  allocator puts them near the TOP of reserved space, binary is at BOTTOM)

### GHC RTS flags
- No flag exists to set `linkerAlwaysPic=false` on aarch64
- `-xm` (linker memory base) only works when `linkerAlwaysPic=false`
- `-xp` sets `linkerAlwaysPic=true` (already the default)

## GHC source references (9.10.3)

- `rts/linker/MMap.c` — `mmapForLinker`: when `linkerAlwaysPic=true`, calls
  `mmapAnywhere` (NULL hint), bypassing `nearImage()` entirely
- `rts/linker/MMap.h` — `LINKER_LOAD_BASE` defined as `&stg_upd_frame_info`
  but unused when `linkerAlwaysPic=true`
- `rts/linker/elf_reloc_aarch64.c:118` — ADRP assertion:
  `CHECK(isInt64(21+12, addend))`
- `rts/linker/elf_got.c` — `makeGot` allocates per-object GOT via
  `mmapAnonForLinker` (separate allocation from code)
- `rts/linker/M32Alloc.c` — `is_okay_address` always returns true when
  `linkerAlwaysPic=true`
- `rts/include/rts/Flags.h` — `DEFAULT_LINKER_ALWAYS_PIC = true` on aarch64
