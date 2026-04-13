# ARM32 (armv7a) Cross-Compilation for Android Wear

## Problem

Building Haskell for armv7a-android (Android Wear / Wear OS watches) requires
Template Haskell cross-compilation via `iserv-proxy-interpreter` running under
QEMU user-mode on an x86_64 build host — the same approach used for aarch64.
However, armv7a introduces several additional challenges:

1. **LLVM ARM backend crashes** when compiling profiled libraries
2. **compiler-rt doesn't recognise armv7a** as a valid ARM32 architecture
3. **Missing ARM EABI division helpers** (`__aeabi_idiv`, `__aeabi_uldivmod`, etc.)
4. **Bionic TLS crash** under QEMU when binary layout changes

## Diagnosis

### Profiling crash (LLVM ARMAsmPrinter)

The armv7a cross-GHC uses LLVM (no NCG for ARM32). Building profiled boot
libraries triggers a crash in `ARMAsmPrinter::emitXXStructor`. The aarch64
cross-GHC works fine because NCG is available.

Fix: Disable profiled libraries for armv7a at three levels:
- `enableProfiledLibs = false` on the cross-GHC
- `armv7aProfilingOverride` disabling `enableLibraryProfiling` per-package
- Patch `generic-builder.nix` to skip the profiled iserv-wrapper variant

### compiler-rt armv7a architecture detection

The nixpkgs `compiler-rt` derivation uses cmake's `builtin-config-ix.cmake` to
detect supported architectures. The `ARM32` set includes `arm`, `armhf`, `armv7`
but NOT `armv7a`. Additionally, Android baremetal builds use `-nodefaultlibs`
which prevents `check_symbol_exists(__arm__)` from linking, so arch detection
fails even with the set fixed.

Fix: `patch-compiler-rt.py` applies three cmake patches:
1. Add `armv7a` to the ARM32 set in `builtin-config-ix.cmake`
2. Add `armv7a_SOURCES` alias in `CMakeLists.txt`
3. For `COMPILER_RT_DEFAULT_TARGET_ONLY`, use `add_default_target_arch()` directly
   (bypasses the broken `detect_target_arch()`)
4. Remove `os_version_check.c` from baremetal builds (requires `pthread.h`)

### LLVM package set: libcxx bootstrap failure

For armv7a, GHC's LLVM backend requires `llvmPackages.clang`. The default
`clang` for Android targets is `libcxxClang`, which depends on `libcxx`. Building
`libcxx` requires a working cross-linker, but the bootstrap `clang-wrapper` only
has GNU binutils (`ld.bfd`), which can't link Android libraries (zstd-compressed
debug sections, missing builtins path).

Fix: Patch the LLVM package set to select `libstdcxxClang` (which has
`libcxx=null`) for Android targets. GHC only needs clang for assembly
(`LLVMAS`), not C++.

### The Bionic TLS crash (the hard one)

With the above fixes, the static `iserv-proxy-interpreter` binary boots under
QEMU but crashes immediately:

```
bionic/libc/bionic/bionic_elf_tls.cpp:96:
  align_checked CHECK 'align != 0 && powerof2(align + 0) && skew < align' failed
```

This crash appeared when ARM EABI division helpers were added to the binary.
Systematic testing established:

| Configuration | Result |
|---|---|
| No `__aeabi_idiv` at all (compiler inlines division) | WORKS |
| `__aeabi_idiv` as global in separate `.o` with `-u` flags | CRASH |
| `__aeabi_idiv` as global in separate `.o` without `-u` flags | CRASH |
| `__aeabi_idiv` as global in same `.o` as `dlsym` | CRASH |
| Pure C implementation (no inline asm) | CRASH |
| Trivial unrelated change to `libdlNative` | WORKS |

The root cause: adding **any** `__aeabi_*` function as a **global symbol** to
`.dynsym` (via `--export-dynamic`) changes the binary's section layout — hash
tables grow, sections shift, alignment changes. Under QEMU user-mode emulation,
this triggers Bionic's TLS initialization check. The check passes mathematically
(`align != 0 && powerof2(align) && skew < align`) on both binaries, suggesting
a QEMU bug in how it presents the ELF program headers to Bionic's startup code.

### Missing ARM EABI division helpers

GHC's LLVM backend targets `armv7-a` which lacks hardware integer divide. The
compiled `.o` files contain calls to:

- `__aeabi_idiv` — signed 32-bit division
- `__aeabi_uidiv` — unsigned 32-bit division
- `__aeabi_idivmod` — signed 32-bit division + modulo
- `__aeabi_uidivmod` — unsigned 32-bit division + modulo
- `__aeabi_uldivmod` — unsigned 64-bit division + modulo
- `__aeabi_ldivmod` — signed 64-bit division + modulo

Android NDK's `compiler-rt` omits these because Android API 21+ effectively
requires Cortex-A7+, which has the IDIV extension. But the cross-compiled `.o`
files loaded by the RTS linker need them resolved at runtime via `dlsym`.

## Solution

### Static functions with dlsym interception

All ARM EABI division helpers are defined as **`static`** functions in
`dl_impl.c`. Being static, they do not appear in `.dynsym` — the binary layout
remains identical to the working (no-aeabi) version.

Our custom `dlsym()` (which already provides dynamic symbol lookup for the
statically linked binary) intercepts lookups for `__aeabi_*` names and returns
pointers to the static implementations:

```c
#if defined(__arm__) || defined(__thumb__)

static unsigned impl_aeabi_uidiv(unsigned numerator, unsigned denominator) {
    /* shift-and-subtract algorithm, no division operators */
}

static int impl_aeabi_idiv(int numerator, int denominator) {
    /* unsigned division + sign handling */
}

/* ... idivmod, uidivmod ... */

static void *lookup_aeabi(const char *symbol) {
    if (strcmp(symbol, "__aeabi_idiv") == 0)  return (void *)impl_aeabi_idiv;
    if (strcmp(symbol, "__aeabi_uidiv") == 0) return (void *)impl_aeabi_uidiv;
    /* ... */
    return NULL;
}

#endif

void *dlsym(void *handle, const char *symbol) {
    if (!g_inited) init_symtab();

#if defined(__arm__) || defined(__thumb__)
    { void *aeabi = lookup_aeabi(symbol);
      if (aeabi) return aeabi; }
#endif

    /* ... normal .dynsym search ... */
}
```

### 64-bit division: naked assembly thunks

The ARM EABI calling convention for `__aeabi_uldivmod` and `__aeabi_ldivmod` is:

```
Input:  r0:r1 = numerator,  r2:r3 = denominator
Output: r0:r1 = quotient,   r2:r3 = remainder
```

This cannot be expressed as a C function (C has no way to return two 64-bit
values in r0:r1 and r2:r3 simultaneously). The solution uses:

1. A standard C function `impl_udivmoddi4(uint64_t num, uint64_t den, uint64_t *rem)`
   that implements 64-bit shift-and-subtract division (no division operators,
   avoiding recursive `__aeabi_uldivmod` calls)

2. A `__attribute__((naked))` assembly thunk that translates calling conventions:

```c
__attribute__((naked))
static void impl_aeabi_uldivmod(void) {
    __asm__ __volatile__ (
        "push {r6, lr}\n"
        "sub sp, sp, #16\n"       // 8 bytes remainder + 4 bytes ptr + 4 pad
        "add r6, sp, #8\n"        // r6 = &remainder
        "str r6, [sp]\n"          // stack arg for C function
        "bl impl_udivmoddi4\n"    // r0-r3 pass through (AAPCS matches EABI)
        "ldr r2, [sp, #8]\n"      // load remainder low
        "ldr r3, [sp, #12]\n"     // load remainder high
        "add sp, sp, #16\n"
        "pop {r6, pc}\n"
    );
}
```

The key insight: the C calling convention (AAPCS) maps `(uint64_t, uint64_t)` to
`r0:r1, r2:r3` — **identical** to the `__aeabi_uldivmod` input convention. So the
thunk only needs to handle the remainder output (the C function returns quotient
in r0:r1, which is already correct).

### Hex diagnostics

A subtle secondary issue: the diagnostic function `diag_num` used decimal
formatting (`val % 10`, `val / 10`) which on ARM32 generates `__aeabi_idiv`
calls. Since this code runs before the division helpers are available, it would
crash. Replaced with `diag_hex` using bitwise operations (`val & 0xf`,
`val >>= 4`).

### Static PIE

ARM32 omits the `-pie` flag used for aarch64. The ARM32 CRT startup doesn't
reliably relocate `.dynsym` entries in static PIE binaries, causing `dlsym` to
return pre-relocation offsets. Plain static linking (`-static` without `-pie`)
works because `d_ptr` values in `_DYNAMIC` are already absolute addresses.

## Files Changed

- `nix/cross-deps.nix` — armv7a profiling overrides, ELF32 types, static flags
- `nix/th-support/dl_impl.c` — static aeabi division + dlsym interception,
  hex diagnostics, 64-bit naked assembly thunks, ELF32 support
- `nix/patch-compiler-rt.py` — compiler-rt armv7a arch fix, LLVM clang fix,
  iserv-wrapper profiling fix
- `nix/patched-nixpkgs.nix` — conditional nixpkgs patching

## Consumer Changes (prrrrrrrrr)

The hatter `test-aeabi-only` / `fix/armv7a-profiling` branch also
includes the Action handles API change (PR #126). Consumer apps need to:

1. Create an `ActionState` with `newActionState`
2. Pre-create `Action` / `OnChange` handles via `runActionM`
3. Pass handles to view functions instead of inline `IO ()` closures
4. Add `maActionState` field to `MobileApp`

## Lessons Learned

1. **npins pin management**: Manually editing `npins/sources.json` only changes
   the `revision` field (metadata). The `url` and `hash` fields determine what's
   actually fetched. Always use `npins update <name>` CLI.

2. **Binary layout sensitivity under QEMU**: Even tiny changes to a static
   binary's `.dynsym` can trigger QEMU/Bionic compatibility issues. When
   providing symbols for the RTS linker, prefer dlsym interception over global
   symbol export.

3. **ARM32 division in C**: Any use of `%` or `/` on ARM32 generates
   `__aeabi_idiv` calls. Use bitwise operations for formatting in code that runs
   before division helpers are available.

4. **ARM EABI 64-bit calling conventions**: `__aeabi_uldivmod` and
   `__aeabi_ldivmod` use a register-pair convention that can't be expressed in C.
   Naked assembly thunks are the cleanest way to bridge to C implementations.
