/*
 * Platform-agnostic HTTP bridge dispatcher.
 *
 * Stores a function pointer filled by the platform (Android/iOS/watchOS).
 * http_request() delegates to the pointer. When no callback is
 * registered (desktop), a stub returns 200 OK with empty body
 * synchronously so that cabal test exercises the round-trip
 * without native code.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "HttpBridge.h"
#include <stdio.h>
#include <string.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnHttpResult(void *ctx, int32_t requestId,
                                 int32_t resultCode, int32_t httpStatus,
                                 const char *headers,
                                 const char *body, int32_t bodyLen);

static void (*g_request_impl)(void *, int32_t, int32_t,
                               const char *, const char *,
                               const char *, int32_t) = NULL;

void http_register_impl(
    void (*request_impl)(void *, int32_t, int32_t,
                          const char *, const char *,
                          const char *, int32_t))
{
    g_request_impl = request_impl;
}

/* ---- Desktop stub ---- */

static void stub_request(void *ctx, int32_t requestId, int32_t method,
                          const char *url, const char *headers,
                          const char *body, int32_t bodyLen)
{
    fprintf(stderr, "[HttpBridge stub] request(method=%d, url=\"%s\")\n",
            method, url);

    /* Return 200 OK with empty body */
    haskellOnHttpResult(ctx, requestId, HTTP_RESULT_SUCCESS, 200,
                         "Content-Type: text/plain\n", "", 0);
}

/* ---- Public API ---- */

void http_request(void *ctx, int32_t requestId, int32_t method,
                  const char *url, const char *headers,
                  const char *body, int32_t bodyLen)
{
    if (g_request_impl) {
        g_request_impl(ctx, requestId, method, url, headers, body, bodyLen);
        return;
    }
    stub_request(ctx, requestId, method, url, headers, body, bodyLen);
}
