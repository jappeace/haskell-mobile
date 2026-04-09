#include <stddef.h>
#include <string.h>
#include <elf.h>
#include <stdint.h>

/*
 * Minimal dlopen/dlsym for a statically linked aarch64 binary.
 *
 * dlopen: returns a fake non-NULL handle (the binary itself).
 * dlsym:  walks the .dynsym table (populated by --export-dynamic
 *         and --hash-style=sysv) to find symbols by name.
 *
 * Requires: -Wl,--export-dynamic -Wl,--hash-style=sysv at link time.
 */

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
            /* SysV hash table: uint32_t nbuckets, nchain.
             * nchain == total number of symbols in .dynsym. */
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
