/*
 * Minimal dlopen/dlsym for a statically linked Android binary.
 *
 * dlopen: returns a fake non-NULL handle (the binary itself).
 * dlsym:  walks the .dynsym table (populated by --export-dynamic)
 *         to find symbols by name.
 *
 * Works for both aarch64 (ELF64) and armv7a (ELF32).
 * Handles both SysV hash (DT_HASH) and GNU hash (DT_GNU_HASH)
 * for determining the symbol count.
 *
 * For non-PIE static binaries (ET_EXEC), d_ptr values in _DYNAMIC
 * are already absolute virtual addresses.
 *
 * Requires: -Wl,--export-dynamic at link time.
 */

#include <stddef.h>
#include <string.h>
#include <elf.h>
#include <stdint.h>
#include <unistd.h>

/* Minimal stderr diagnostic (avoids stdio dependency).
 * Uses hex to avoid __aeabi_idiv references from decimal division —
 * on ARM32, val%10 generates __aeabi_idiv calls that pull in division
 * helpers from compiler-rt, breaking Bionic's static TLS init. */
static void diag(const char *msg) {
    write(2, msg, strlen(msg));
}
static void diag_hex(const char *label, unsigned long val) {
    char buf[20];
    const char *hex = "0123456789abcdef";
    int i = 19;
    buf[i] = 0;
    if (val == 0) { buf[--i] = '0'; }
    else { while (val > 0 && i > 0) { buf[--i] = hex[val & 0xf]; val >>= 4; } }
    buf[--i] = 'x'; buf[--i] = '0';
    diag(label);
    diag(buf + i);
    diag("\n");
}

/* Architecture-independent ELF types. */
#if __SIZEOF_POINTER__ == 8
typedef Elf64_Dyn ElfDyn;
typedef Elf64_Sym ElfSym;
typedef Elf64_Addr ElfAddr;
#else
typedef Elf32_Dyn ElfDyn;
typedef Elf32_Sym ElfSym;
typedef Elf32_Addr ElfAddr;
#endif

/* _DYNAMIC is provided by the linker. */
extern ElfDyn _DYNAMIC[] __attribute__((weak));

static ElfSym     *g_symtab  = NULL;
static const char *g_strtab  = NULL;
static uint32_t    g_strsz   = 0;
static uint32_t    g_nsyms   = 0;
static int         g_inited  = 0;

/* Compute nsyms from GNU hash table. */
static uint32_t gnu_hash_nsyms(const uint32_t *gnu_hash) {
    uint32_t nbuckets   = gnu_hash[0];
    uint32_t symoffset  = gnu_hash[1];
    uint32_t bloom_size = gnu_hash[2];
#if __SIZEOF_POINTER__ == 8
    const uint32_t *buckets = gnu_hash + 4 + bloom_size * 2;
#else
    const uint32_t *buckets = gnu_hash + 4 + bloom_size;
#endif
    const uint32_t *chains  = buckets + nbuckets;

    uint32_t max_idx = 0;
    uint32_t i;
    for (i = 0; i < nbuckets; i++) {
        if (buckets[i] > max_idx)
            max_idx = buckets[i];
    }
    if (max_idx < symoffset) return symoffset;

    const uint32_t *chain_entry = chains + (max_idx - symoffset);
    while (!(*chain_entry & 1)) {
        max_idx++;
        chain_entry++;
    }
    return max_idx + 1;
}

static void init_symtab(void) {
    ElfDyn *d;
    const uint32_t *gnu_hash_ptr = NULL;
    g_inited = 1;
    diag("dl_impl: init_symtab called\n");
    if (!_DYNAMIC) { diag("dl_impl: _DYNAMIC is NULL!\n"); return; }
    for (d = _DYNAMIC; d->d_tag != DT_NULL; d++) {
        switch (d->d_tag) {
        case DT_SYMTAB:
            g_symtab = (ElfSym *)(uintptr_t)d->d_un.d_ptr;
            break;
        case DT_STRTAB:
            g_strtab = (const char *)(uintptr_t)d->d_un.d_ptr;
            break;
        case DT_STRSZ:
            g_strsz = (uint32_t)d->d_un.d_val;
            break;
        case DT_HASH: {
            uint32_t *h = (uint32_t *)(uintptr_t)d->d_un.d_ptr;
            g_nsyms = h[1];
            break;
        }
        case DT_GNU_HASH:
            gnu_hash_ptr = (const uint32_t *)(uintptr_t)d->d_un.d_ptr;
            break;
        }
    }
    if (g_nsyms == 0 && gnu_hash_ptr) {
        diag("dl_impl: using DT_GNU_HASH fallback\n");
        g_nsyms = gnu_hash_nsyms(gnu_hash_ptr);
    }
    diag_hex("dl_impl: g_nsyms = ", g_nsyms);
    diag_hex("dl_impl: g_strsz = ", g_strsz);
    diag_hex("dl_impl: g_symtab = ", (unsigned long)g_symtab);
    diag_hex("dl_impl: g_strtab = ", (unsigned long)g_strtab);
}

/*
 * ARM EABI integer division helpers (ARM32 only).
 *
 * GHC's LLVM backend emits __aeabi_idiv calls for ARM32 code loaded
 * by the RTS linker during TH evaluation.  The Android NDK doesn't
 * provide these (assumes hardware divide).
 *
 * IMPORTANT: these must be static to avoid appearing in .dynsym.
 * Adding them as global symbols changes the binary layout enough to
 * trigger a Bionic TLS alignment check failure under QEMU.
 * Our dlsym intercepts lookups for these names and returns pointers
 * to the static implementations.
 */
#if defined(__arm__) || defined(__thumb__)

static unsigned impl_aeabi_uidiv(unsigned numerator, unsigned denominator) {
    if (denominator == 0) return 0;
    unsigned quotient = 0;
    unsigned bit = 1;
    while (denominator <= numerator && !(denominator & (1u << 31))) {
        denominator <<= 1;
        bit <<= 1;
    }
    while (bit) {
        if (numerator >= denominator) {
            numerator -= denominator;
            quotient |= bit;
        }
        denominator >>= 1;
        bit >>= 1;
    }
    return quotient;
}

static int impl_aeabi_idiv(int numerator, int denominator) {
    int negative = 0;
    if (numerator < 0) { numerator = -numerator; negative = !negative; }
    if (denominator < 0) { denominator = -denominator; negative = !negative; }
    unsigned result = impl_aeabi_uidiv((unsigned)numerator, (unsigned)denominator);
    return negative ? -(int)result : (int)result;
}

typedef struct { int quot; int rem; } idivmod_result_t;
static idivmod_result_t impl_aeabi_idivmod(int numerator, int denominator) {
    int quot = impl_aeabi_idiv(numerator, denominator);
    int rem = numerator - quot * denominator;
    return (idivmod_result_t){quot, rem};
}

typedef struct { unsigned quot; unsigned rem; } uidivmod_result_t;
static uidivmod_result_t impl_aeabi_uidivmod(unsigned numerator,
                                              unsigned denominator) {
    unsigned quot = impl_aeabi_uidiv(numerator, denominator);
    unsigned rem = numerator - quot * denominator;
    return (uidivmod_result_t){quot, rem};
}

/*
 * 64-bit division helpers for __aeabi_uldivmod / __aeabi_ldivmod.
 *
 * These ARM EABI functions use a non-standard calling convention:
 *   Input:  r0:r1 = numerator, r2:r3 = denominator
 *   Output: r0:r1 = quotient,  r2:r3 = remainder
 * This can't be expressed as a C function, so we use naked assembly
 * thunks that call standard C division implementations.
 *
 * The C functions impl_udivmoddi4 / impl_ldivmoddi4 use the standard
 * AAPCS calling convention: (uint64_t, uint64_t, uint64_t*) -> uint64_t.
 * The first two uint64_t args occupy r0-r3 identically to __aeabi, so
 * the thunks just push a remainder pointer on the stack and load back
 * the remainder into r2:r3 afterward.
 */

/* 64-bit unsigned division - shift-and-subtract algorithm.
 * No division operators to avoid recursive __aeabi_uldivmod calls.
 * noinline + used: ensure the symbol exists for the asm bl target. */
__attribute__((noinline, used))
static unsigned long long impl_udivmoddi4(unsigned long long numerator,
                                           unsigned long long denominator,
                                           unsigned long long *remainder) {
    if (denominator == 0) {
        if (remainder) *remainder = 0;
        return 0;
    }
    unsigned long long quotient = 0;
    unsigned long long bit = 1;
    while (denominator <= numerator && !(denominator & (1ULL << 63))) {
        denominator <<= 1;
        bit <<= 1;
    }
    while (bit) {
        if (numerator >= denominator) {
            numerator -= denominator;
            quotient |= bit;
        }
        denominator >>= 1;
        bit >>= 1;
    }
    if (remainder) *remainder = numerator;
    return quotient;
}

/* 64-bit signed division via unsigned division. */
__attribute__((noinline, used))
static long long impl_ldivmoddi4(long long numerator, long long denominator,
                                  long long *remainder) {
    int neg_quot = 0, neg_rem = 0;
    unsigned long long unum, uden, urem, uquot;
    if (numerator < 0) { numerator = -numerator; neg_quot = !neg_quot; neg_rem = 1; }
    if (denominator < 0) { denominator = -denominator; neg_quot = !neg_quot; }
    unum = (unsigned long long)numerator;
    uden = (unsigned long long)denominator;
    uquot = impl_udivmoddi4(unum, uden, &urem);
    if (remainder)
        *remainder = neg_rem ? -(long long)urem : (long long)urem;
    return neg_quot ? -(long long)uquot : (long long)uquot;
}

/* Assembly thunks matching __aeabi_{u,l}divmod calling convention.
 * AAPCS maps (uint64_t, uint64_t) to r0:r1, r2:r3 — same as __aeabi.
 * The uint64_t* remainder pointer is passed on the stack ([sp+0]).
 * Stack layout: [sp+0..3] = &rem, [sp+4..7] = pad, [sp+8..15] = rem */
__attribute__((naked))
static void impl_aeabi_uldivmod(void) {
    __asm__ __volatile__ (
        "push {r6, lr}\n"
        "sub sp, sp, #16\n"
        "add r6, sp, #8\n"
        "str r6, [sp]\n"
        "bl impl_udivmoddi4\n"
        "ldr r2, [sp, #8]\n"
        "ldr r3, [sp, #12]\n"
        "add sp, sp, #16\n"
        "pop {r6, pc}\n"
    );
}

__attribute__((naked))
static void impl_aeabi_ldivmod(void) {
    __asm__ __volatile__ (
        "push {r6, lr}\n"
        "sub sp, sp, #16\n"
        "add r6, sp, #8\n"
        "str r6, [sp]\n"
        "bl impl_ldivmoddi4\n"
        "ldr r2, [sp, #8]\n"
        "ldr r3, [sp, #12]\n"
        "add sp, sp, #16\n"
        "pop {r6, pc}\n"
    );
}

static void *lookup_aeabi(const char *symbol) {
    if (strcmp(symbol, "__aeabi_idiv") == 0)     return (void *)impl_aeabi_idiv;
    if (strcmp(symbol, "__aeabi_uidiv") == 0)    return (void *)impl_aeabi_uidiv;
    if (strcmp(symbol, "__aeabi_idivmod") == 0)  return (void *)impl_aeabi_idivmod;
    if (strcmp(symbol, "__aeabi_uidivmod") == 0) return (void *)impl_aeabi_uidivmod;
    if (strcmp(symbol, "__aeabi_uldivmod") == 0) return (void *)impl_aeabi_uldivmod;
    if (strcmp(symbol, "__aeabi_ldivmod") == 0)  return (void *)impl_aeabi_ldivmod;
    return NULL;
}

#endif /* __arm__ || __thumb__ */

void *dlopen(const char *filename, int flags) {
    (void)filename; (void)flags;
    return (void *)(uintptr_t)1;
}

char *dlerror(void) { return NULL; }

void *dlsym(void *handle, const char *symbol) {
    uint32_t i;
    (void)handle;
    if (!g_inited) init_symtab();

#if defined(__arm__) || defined(__thumb__)
    /* Check ARM EABI builtins first (static, not in .dynsym). */
    {
        void *aeabi = lookup_aeabi(symbol);
        if (aeabi) return aeabi;
    }
#endif

    if (!g_symtab || !g_strtab) return NULL;
    for (i = 0; i < g_nsyms; i++) {
        if (g_strsz > 0 && g_symtab[i].st_name >= g_strsz) continue;
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
