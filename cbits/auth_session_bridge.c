/*
 * Platform-agnostic auth session bridge dispatcher.
 *
 * Stores a function pointer filled by the platform (Android/iOS/watchOS).
 * auth_session_start() delegates to the pointer. When no callback is
 * registered (desktop), a stub builds a fake redirect URL and fires
 * haskellOnAuthSessionResult synchronously so that cabal test exercises
 * the round-trip without native code.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "AuthSessionBridge.h"
#include <stdio.h>
#include <string.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnAuthSessionResult(void *ctx, int32_t requestId,
                                        int32_t statusCode,
                                        const char *redirectUrl,
                                        const char *errorMessage);

static void (*g_start_impl)(void *, int32_t, const char *, const char *) = NULL;

void auth_session_register_impl(
    void (*start_impl)(void *, int32_t, const char *, const char *))
{
    g_start_impl = start_impl;
}

/* ---- Desktop stub ---- */

static void stub_start(void *ctx, int32_t requestId,
                       const char *authUrl, const char *callbackScheme)
{
    fprintf(stderr, "[AuthSessionBridge stub] start(url=\"%s\", scheme=\"%s\")\n",
            authUrl, callbackScheme);

    /* Build a fake redirect URL: <scheme>://callback?code=DESKTOP_STUB_CODE&state=test */
    char redirectUrl[512];
    snprintf(redirectUrl, sizeof(redirectUrl),
             "%s://callback?code=DESKTOP_STUB_CODE&state=test", callbackScheme);

    haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_SUCCESS, redirectUrl, NULL);
}

/* ---- Public API ---- */

void auth_session_start(void *ctx, int32_t requestId,
                        const char *authUrl, const char *callbackScheme)
{
    if (g_start_impl) {
        g_start_impl(ctx, requestId, authUrl, callbackScheme);
        return;
    }
    stub_start(ctx, requestId, authUrl, callbackScheme);
}
