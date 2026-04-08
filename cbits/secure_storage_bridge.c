/*
 * Platform-agnostic secure storage bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS/watchOS).
 * Each secure_storage_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), an in-memory linked list
 * provides basic key-value storage so that cabal build/test works
 * without native code.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "SecureStorageBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnSecureStorageResult(void *ctx, int32_t requestId,
                                         int32_t statusCode, const char *value);

static void (*g_write_impl)(void *, int32_t, const char *, const char *) = NULL;
static void (*g_read_impl)(void *, int32_t, const char *) = NULL;
static void (*g_delete_impl)(void *, int32_t, const char *) = NULL;

void secure_storage_register_impl(
    void (*write_impl)(void *, int32_t, const char *, const char *),
    void (*read_impl)(void *, int32_t, const char *),
    void (*delete_impl)(void *, int32_t, const char *))
{
    g_write_impl = write_impl;
    g_read_impl = read_impl;
    g_delete_impl = delete_impl;
}

/* ---- Desktop in-memory stub (singly-linked list) ---- */

typedef struct KVNode {
    char *key;
    char *value;
    struct KVNode *next;
} KVNode;

static KVNode *g_store = NULL;

static KVNode *find_node(const char *key)
{
    KVNode *node = g_store;
    while (node) {
        if (strcmp(node->key, key) == 0) return node;
        node = node->next;
    }
    return NULL;
}

static void stub_write(void *ctx, int32_t requestId, const char *key, const char *value)
{
    fprintf(stderr, "[SecureStorageBridge stub] write(key=\"%s\")\n", key);
    KVNode *existing = find_node(key);
    if (existing) {
        free(existing->value);
        existing->value = strdup(value);
    } else {
        KVNode *node = malloc(sizeof(KVNode));
        node->key = strdup(key);
        node->value = strdup(value);
        node->next = g_store;
        g_store = node;
    }
    haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, NULL);
}

static void stub_read(void *ctx, int32_t requestId, const char *key)
{
    fprintf(stderr, "[SecureStorageBridge stub] read(key=\"%s\")\n", key);
    KVNode *node = find_node(key);
    if (node) {
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, node->value);
    } else {
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_NOT_FOUND, NULL);
    }
}

static void stub_delete(void *ctx, int32_t requestId, const char *key)
{
    fprintf(stderr, "[SecureStorageBridge stub] delete(key=\"%s\")\n", key);
    KVNode **prev = &g_store;
    KVNode *node = g_store;
    while (node) {
        if (strcmp(node->key, key) == 0) {
            *prev = node->next;
            free(node->key);
            free(node->value);
            free(node);
            haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, NULL);
            return;
        }
        prev = &node->next;
        node = node->next;
    }
    haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, NULL);
}

/* ---- Public API ---- */

void secure_storage_write(void *ctx, int32_t requestId, const char *key, const char *value)
{
    if (g_write_impl) {
        g_write_impl(ctx, requestId, key, value);
        return;
    }
    stub_write(ctx, requestId, key, value);
}

void secure_storage_read(void *ctx, int32_t requestId, const char *key)
{
    if (g_read_impl) {
        g_read_impl(ctx, requestId, key);
        return;
    }
    stub_read(ctx, requestId, key);
}

void secure_storage_delete(void *ctx, int32_t requestId, const char *key)
{
    if (g_delete_impl) {
        g_delete_impl(ctx, requestId, key);
        return;
    }
    stub_delete(ctx, requestId, key);
}
