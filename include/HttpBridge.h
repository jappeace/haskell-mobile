#ifndef HTTP_BRIDGE_H
#define HTTP_BRIDGE_H

#include <stdint.h>

/* HTTP result codes (must match HaskellMobile.Http) */
#define HTTP_RESULT_SUCCESS       0
#define HTTP_RESULT_NETWORK_ERROR 1
#define HTTP_RESULT_TIMEOUT       2

/* HTTP method codes (must match HaskellMobile.Http) */
#define HTTP_METHOD_GET    0
#define HTTP_METHOD_POST   1
#define HTTP_METHOD_PUT    2
#define HTTP_METHOD_DELETE 3

/*
 * Platform-agnostic HTTP bridge.
 *
 * Haskell calls http_request() through this wrapper.
 * When no platform callback is registered (desktop), a stub returns
 * a 200 OK with empty body synchronously.
 *
 * On Android/iOS the platform-specific setup function fills in a real
 * implementation via http_register_impl().
 */

/* Start an HTTP request.
 * ctx:        opaque Haskell context pointer (passed through to callback).
 * requestId:  opaque ID from Haskell (used to dispatch the result).
 * method:     HTTP_METHOD_GET (0), HTTP_METHOD_POST (1), etc.
 * url:        null-terminated URL string.
 * headers:    newline-delimited "Key: Value\n" header string, or NULL.
 * body:       request body bytes, or NULL.
 * bodyLen:    length of body in bytes, or 0. */
void http_request(void *ctx, int32_t requestId, int32_t method,
                  const char *url, const char *headers,
                  const char *body, int32_t bodyLen);

/* Register the platform-specific implementation.
 * Called by platform setup functions (setup_android_http_bridge, etc). */
void http_register_impl(
    void (*request_impl)(void *, int32_t, int32_t,
                         const char *, const char *,
                         const char *, int32_t));

#endif /* HTTP_BRIDGE_H */
