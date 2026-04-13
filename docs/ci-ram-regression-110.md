# CI RAM Regression: Boot Package Whole-Archive Bloat (Issue #110)

Post-mortem analysis of why CI suddenly needed more emulator RAM in April 2026, which changes caused it, and how it was resolved.

---

## Executive Summary

Commit `5442328` ("Fix collect-deps.nix") added GHC boot package `.a` files to the cross-compilation dependency collection. These files landed in the same directory that `mkAndroidLib` wraps with `--whole-archive`, causing the linker to pull every symbol from every boot package into the shared library. The resulting `.so` ballooned from ~80MB to ~373MB, triggering OOM kills inside the Android emulator's 4096MB RAM.

The issue was resolved in two steps: a workaround bumped emulator RAM to 6144MB (`0ad78b8`), and the proper fix moved boot package archives to a separate directory linked without `--whole-archive` (`1bcfed3`). Both landed in PR #101.

---

## Timeline

| Date | Commit | Event |
|------|--------|-------|
| Apr 8 13:55 | `98ac040` | PR #57 (Image widget) merged. Last fully green CI run. 6 APKs, `.so` ~80MB each. |
| Apr 8 14:11 | `5442328` | collect-deps.nix updated to include GHC boot package `.a` files in `$out/lib/`. |
| Apr 8 ~15:00 | — | Android CI jobs start timing out (45-min limit). Emulator app OOM-killed. |
| Apr 8 15:59 | `92a5ee3` | "ci: retrigger Android jobs (emulator tests cancelled by runner timeout)" |
| Apr 8 19:23 | `0ad78b8` | Workaround: emulator RAM 4096 -> 6144 MB, switch from `google_apis_playstore` to `google_apis`. |
| Apr 8 18:59 | `1bcfed3` | Proper fix: boot packages moved to `$out/lib-boot/`, linked after `--no-whole-archive`. |
| Apr 8 19:23 | — | PR #101 CI run passes. |

---

## Root Cause

### The collect-deps change

`collect-deps.nix` gathers static archives (`.a` files) from Haskell dependencies so `mkAndroidLib` can link them into the Android shared library. Commit `5442328` added a new step to collect boot package `.a` files from the GHC installation:

```nix
# Collect boot package .a files from the GHC.
find ${ghc}/lib -name 'libHS*.a' ! -name '*_p.a' ! -name '*_thr*' ! -name '*-ghc*' | while read aFile; do
    aName=$(basename "$aFile")
    if [ ! -f "$out/lib/$aName" ]; then
      cp "$aFile" $out/lib/
    fi
done
```

This was needed so consumer deps (e.g. sqlite-simple) could reference boot packages like `os-string`, `mtl`, and `stm` that `mkAndroidLib` doesn't link by default. Without it, the linker would fail with undefined symbol errors for any consumer dep that transitively depended on a boot package.

### The whole-archive interaction

The problem was that these boot archives landed in `$out/lib/` — the same directory that `mkAndroidLib` wraps with `--whole-archive`:

```bash
# In lib.nix mkAndroidLib:
-optl-Wl,--whole-archive \
  ... boot packages like base, containers, bytestring, parsec ...
  $(for a in ${crossDeps}/lib/*.a; do echo -n "-optl$a "; done)
-optl-Wl,--no-whole-archive
```

`--whole-archive` forces the linker to include **every object file** from an archive, even if no symbols are referenced. This is necessary for the Haskell RTS and a few core libraries (to ensure FFI exports and module initialisation are included), but catastrophic when applied to every boot package.

### The size explosion

The GHC boot packages include large libraries like `base`, `containers`, `bytestring`, `parsec`, `text`, and dozens more. Whole-archiving all of them pulled hundreds of megabytes of unreferenced code into the `.so`:

| App | Before (`98ac040`) | After (`5442328`) | After fix (`1bcfed3`) |
|-----|--------------------|--------------------|----------------------|
| Counter | ~80 MB | ~373 MB | ~80 MB |
| Consumer (sqlite-simple) | ~103 MB | ~406 MB | ~103 MB |

### The OOM cascade

1. The bloated `.so` is loaded into the Android emulator via the APK
2. The emulator has 4096 MB RAM (configured in `emulator-all.nix`)
3. The oversized library consumes much more memory at load time
4. The Haskell RTS requests additional heap for normal operation
5. Android's low memory killer terminates the app
6. The test script waits for logcat output that never arrives
7. The 60-second per-phase timeout expires, and eventually the 45-minute CI job timeout triggers

---

## Resolution

### Workaround (commit `0ad78b8`)

- Increased emulator RAM from 4096 MB to 6144 MB (both `hw.ramSize` in `config.ini` and the `-memory` CLI flag)
- Switched the system image from `google_apis_playstore` to `google_apis`, removing Play Store services memory overhead
- Added `|| true` to logcat poll commands to prevent silent script death on transient ADB disconnects

### Proper fix (commit `1bcfed3`)

Moved boot package `.a` files to a separate `$out/lib-boot/` directory:

```nix
# In collect-deps.nix:
cp "$aFile" $out/lib-boot/    # was: $out/lib/
```

And linked them **after** `--no-whole-archive` in `lib.nix`:

```nix
# In mkAndroidLib:
-optl-Wl,--no-whole-archive \
  $(for a in ${crossDeps}/lib-boot/*.a; do echo -n "-optl$a "; done)
```

This way the linker only pulls in symbols that are actually referenced, keeping the `.so` at its normal size while still resolving boot package symbols needed by consumer deps.

---

## Prevention: `.so` Size Guard

Two layers of protection:

**CI test suite (hard fail):** `nix/emulator-all.nix` checks the `.so` size of every test app before booting the emulator. If any `.so` exceeds 120 MB, the test fails immediately with a clear diagnostic. The counter app `.so` is ~80 MB, so 120 MB catches bloat early while leaving room for legitimate growth from new features.

```
OK    hatter-android .so is 79 MB
OK    hatter-scroll-android .so is 79 MB
...
FAIL  hatter-android .so is 373 MB (limit: 120 MB)

FATAL: .so size limit exceeded. This usually means boot package .a files
ended up in the --whole-archive link group. See docs/ci-ram-regression-110.md
```

**`mkAndroidLib` (warning):** The user-facing builder prints the `.so` size and warns if it exceeds `soMaxSizeMB` (default 200 MB). This is a soft warning, not a hard fail, because consumer apps (e.g. prrrrrrrrr with sqlite-simple) may legitimately be larger.

---

## Remaining State

The emulator RAM remains at 6144 MB even though the proper fix landed. This provides headroom for future growth (more test APKs, larger consumer deps) but could be reduced back to 4096 MB if CI resource usage becomes a concern.

---

## Lessons

1. **`--whole-archive` is a blunt instrument.** Any `.a` file placed in the whole-archive link group gets fully included. New archives added to that directory must be intentional.

2. **Separate link groups for different archive roles.** Boot packages, consumer deps, and core RTS libraries have different linking requirements. Mixing them in a single directory conflates these roles.

3. **Binary size is a canary for memory issues.** A 4.5x increase in `.so` size directly translates to increased runtime memory pressure. The `.so` size guard in the CI test suite now catches this automatically before the emulator even boots.
