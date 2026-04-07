/*
 * mac2watchos — Rewrite Mach-O platform tags from macOS to watchOS.
 *
 * Based on zw3rk/mobile-core-tools mac2ios.c, adapted for watchOS.
 * Patches LC_BUILD_VERSION platform from PLATFORM_MACOS (1) to
 * PLATFORM_WATCHOS (4) or PLATFORM_WATCHOSSIMULATOR (9), and
 * rewrites legacy LC_VERSION_MIN_MACOSX to LC_VERSION_MIN_WATCHOS.
 *
 * Usage:
 *   mac2watchos [-s] FILE
 *     -s  set platform to WATCHOSSIMULATOR (default: WATCHOS)
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

/* ---------- Mach-O structures (from mobile-core-tools/macho.h) ---------- */

typedef int     cpu_type_t;
typedef int     cpu_subtype_t;

typedef struct _mach_header_64 {
    uint32_t      magic;
    cpu_type_t    cputype;
    cpu_subtype_t cpusubtype;
    uint32_t      filetype;
    uint32_t      ncmds;
    uint32_t      sizeofcmds;
    uint32_t      flags;
    uint32_t      reserved;
} mach_header_64;

typedef struct _load_command {
    uint32_t cmd;
    uint32_t cmdsize;
} load_command;

struct build_version_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t platform;
    uint32_t minos;
    uint32_t sdk;
    uint32_t ntools;
};

#define LC_VERSION_MIN_MACOSX   0x24
#define LC_VERSION_MIN_WATCHOS  0x30
#define LC_BUILD_VERSION        0x32

#define PLATFORM_WATCHOS            4
#define PLATFORM_WATCHOSSIMULATOR   9

/* ---------- AR archive header (from mobile-core-tools/ar.h) ---------- */

typedef struct _ar_header {
    char ident[16];
    char mtime[12];
    char oid[6];
    char uid[6];
    char mode[8];
    char size[10];
    char end[2];
} ar_header;

/* ---------- Implementation ---------- */

/* 64 KB buffer — load commands are limited to ~16 KB, header is ~64 bytes */
static uint8_t buffer[64 * 1024];

static void patch_object(FILE *fp, size_t len, int platform) {
    int pos = ftell(fp);

    fread(buffer, sizeof(buffer), 1, fp);

    mach_header_64 *hdr = (mach_header_64 *)buffer;

    if (!(hdr->magic == 0xfeedface      /* 32-bit  */
       || hdr->magic == 0xfeedfacf      /* 64-bit  */
       || hdr->magic == 0xcafebabe)) {  /* Universal */
        fseek(fp, pos, SEEK_SET);
        return;
    }

    size_t offset = sizeof(mach_header_64);
    load_command *cmd;
    while (offset < sizeof(mach_header_64) + hdr->sizeofcmds) {
        cmd = (load_command *)(buffer + offset);
        switch (cmd->cmd) {
        case LC_VERSION_MIN_MACOSX: {
            cmd->cmd = LC_VERSION_MIN_WATCHOS;
            printf("Changing LC_VERSION_MIN_ from: %d -> %d\n",
                   LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_WATCHOS);
            fseek(fp, pos + offset, SEEK_SET);
            fwrite(buffer + offset, sizeof(struct build_version_command), 1, fp);
            break;
        }
        case LC_BUILD_VERSION: {
            struct build_version_command *bvc =
                (struct build_version_command *)(buffer + offset);
            printf("Changing platform from: %d -> %d\n",
                   bvc->platform, platform);
            bvc->platform = platform;
            fseek(fp, pos + offset, SEEK_SET);
            fwrite(buffer + offset, sizeof(struct build_version_command), 1, fp);
            break;
        }
        default:
            break;
        }
        offset += cmd->cmdsize;
    }
    fseek(fp, pos, SEEK_SET);
}

static uint32_t parse_ar_size(char *s, size_t maxlen) {
    uint32_t ret = 0;
    for (size_t i = 0; i < maxlen; i++) {
        if (s[i] < 48 || s[i] > 57) break;
        ret = ret * 10 + s[i] - 48;
    }
    return ret;
}

static int parse_archive(FILE *fp, int platform) {
    int pos = ftell(fp);

    char magic[8];
    fread(&magic, sizeof(magic), 1, fp);
    if (0 != strncmp(magic, "!<arch>\n", 8)) {
        printf("Doesn't look like an archive. Should start with '!<arch>\\n'\n");
        return 1;
    }

    ar_header entry;
    char ident[128];
    while (fread(&entry, sizeof(ar_header), 1, fp)) {
        size_t payload = parse_ar_size(entry.size, 10);
        if (0 == strncmp(entry.ident, "#1/", 3)) {
            int ident_len = parse_ar_size(entry.ident + 3, 16 - 3);
            fread(&ident, ident_len, 1, fp);
            payload -= ident_len;
        } else {
            strncpy(ident, entry.ident, 16);
        }
        printf("%6zu %s\n", payload, ident);
        if (0 != strncmp(ident, "__.SYMDEF", 9))
            patch_object(fp, payload, platform);
        fseek(fp, payload, SEEK_CUR);
    }
    fseek(fp, pos, SEEK_SET);
    return 0;
}

int main(int argc, char **argv) {
    opterr = 0;
    int c;
    int platform = PLATFORM_WATCHOS;

    while ((c = getopt(argc, argv, "hs")) != -1) {
        switch (c) {
        case 'h':
            printf("mac2watchos -- tool to rewrite the platform in object files\n");
            printf("Usage: mac2watchos FILE\n");
            printf(" -h show this help message\n");
            printf(" -s set platform to WATCHOSSIMULATOR\n");
            printf(" by default we set WATCHOS\n");
            return EXIT_SUCCESS;
        case 's':
            platform = PLATFORM_WATCHOSSIMULATOR;
            break;
        default:
            break;
        }
    }

    if (optind == argc) {
        printf("expecting FILE argument.");
        return EXIT_FAILURE;
    }

    FILE *ptr = fopen(argv[optind], "rb+");
    if (NULL == ptr) {
        printf("Failed to open %s\n", argv[optind]);
        return EXIT_FAILURE;
    }

    int ret = parse_archive(ptr, platform);
    fclose(ptr);

    return ret;
}
