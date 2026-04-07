/*
 * Platform-agnostic permission bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS).
 * Each permission_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), functions log to stderr
 * and auto-grant so that cabal build/test works without native code.
 *
 * The opaque Haskell context pointer is threaded through permission_request
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "PermissionBridge.h"
#include <stdio.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnPermissionResult(void *ctx, int32_t requestId, int32_t statusCode);

static void (*g_request_impl)(void *, int32_t, int32_t) = NULL;
static int32_t (*g_check_impl)(int32_t) = NULL;

void permission_register_impl(
    void (*request)(void *, int32_t, int32_t),
    int32_t (*check)(int32_t))
{
    g_request_impl = request;
    g_check_impl = check;
}

void permission_request(void *ctx, int32_t permissionCode, int32_t requestId)
{
    if (g_request_impl) {
        g_request_impl(ctx, permissionCode, requestId);
        return;
    }
    /* Desktop stub: auto-grant and dispatch synchronously */
    fprintf(stderr, "[PermissionBridge stub] permission_request(code=%d, id=%d) -> auto-grant\n",
            permissionCode, requestId);
    haskellOnPermissionResult(ctx, requestId, PERMISSION_GRANTED);
}

int32_t permission_check(int32_t permissionCode)
{
    if (g_check_impl) {
        return g_check_impl(permissionCode);
    }
    /* Desktop stub: always granted */
    fprintf(stderr, "[PermissionBridge stub] permission_check(code=%d) -> granted\n",
            permissionCode);
    return PERMISSION_GRANTED;
}
