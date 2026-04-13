/*
 * Platform-agnostic sign-in bridge dispatcher.
 *
 * Stores a function pointer filled by the platform (Android/iOS/watchOS).
 * platform_sign_in_start() delegates to the pointer. When no callback is
 * registered (desktop), a stub returns fake credentials and fires
 * haskellOnPlatformSignInResult synchronously so that cabal test exercises
 * the round-trip without native code.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "PlatformSignInBridge.h"
#include <stdio.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnPlatformSignInResult(void *ctx, int32_t requestId,
                                           int32_t statusCode,
                                           const char *identityToken,
                                           const char *userId,
                                           const char *email,
                                           const char *fullName,
                                           int32_t provider);

static void (*g_start_impl)(void *, int32_t, int32_t) = NULL;

void platform_sign_in_register_impl(
    void (*start_impl)(void *, int32_t, int32_t))
{
    g_start_impl = start_impl;
}

/* ---- Desktop stub ---- */

static void stub_start(void *ctx, int32_t requestId, int32_t provider)
{
    fprintf(stderr, "[PlatformSignInBridge stub] start(provider=%d)\n", provider);

    if (provider == PLATFORM_SIGN_IN_APPLE) {
        haskellOnPlatformSignInResult(ctx, requestId,
            PLATFORM_SIGN_IN_SUCCESS,
            "DESKTOP_STUB_APPLE_TOKEN",
            "apple-stub-user-001",
            "stub@privaterelay.appleid.com",
            "Desktop Tester",
            PLATFORM_SIGN_IN_APPLE);
    } else if (provider == PLATFORM_SIGN_IN_GOOGLE) {
        haskellOnPlatformSignInResult(ctx, requestId,
            PLATFORM_SIGN_IN_SUCCESS,
            "DESKTOP_STUB_GOOGLE_TOKEN",
            "google-stub-user-001",
            "tester@gmail.com",
            "Desktop Tester",
            PLATFORM_SIGN_IN_GOOGLE);
    } else {
        haskellOnPlatformSignInResult(ctx, requestId,
            PLATFORM_SIGN_IN_ERROR,
            NULL, NULL, NULL,
            "unknown provider",
            provider);
    }
}

/* ---- Public API ---- */

void platform_sign_in_start(void *ctx, int32_t requestId, int32_t provider)
{
    if (g_start_impl) {
        g_start_impl(ctx, requestId, provider);
        return;
    }
    stub_start(ctx, requestId, provider);
}
