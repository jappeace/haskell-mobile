/*
 * Platform-agnostic camera bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS).
 * Each camera_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), capture_photo dispatches
 * a success result with a dummy file path ("/tmp/stub_photo.jpg"),
 * and start_video dispatches a success result with "/tmp/stub_video.mp4"
 * so that cabal test can verify the callback path.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "CameraBridge.h"
#include <stdio.h>

/* Haskell FFI export (called from desktop stub to dispatch result back) */
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                   int32_t statusCode, const char *filePath);

static void (*g_start_session_impl)(void *, int32_t) = NULL;
static void (*g_stop_session_impl)(void) = NULL;
static void (*g_capture_photo_impl)(void *, int32_t) = NULL;
static void (*g_start_video_impl)(void *, int32_t) = NULL;
static void (*g_stop_video_impl)(void) = NULL;

void camera_register_impl(
    void (*start_session_impl)(void *, int32_t),
    void (*stop_session_impl)(void),
    void (*capture_photo_impl)(void *, int32_t),
    void (*start_video_impl)(void *, int32_t),
    void (*stop_video_impl)(void))
{
    g_start_session_impl = start_session_impl;
    g_stop_session_impl = stop_session_impl;
    g_capture_photo_impl = capture_photo_impl;
    g_start_video_impl = start_video_impl;
    g_stop_video_impl = stop_video_impl;
}

/* ---- Desktop stubs ---- */

static void stub_start_session(void *ctx, int32_t source)
{
    fprintf(stderr, "[CameraBridge stub] camera_start_session(source=%d) -> no-op\n", source);
}

static void stub_stop_session(void)
{
    fprintf(stderr, "[CameraBridge stub] camera_stop_session() -> no-op\n");
}

static void stub_capture_photo(void *ctx, int32_t requestId)
{
    fprintf(stderr, "[CameraBridge stub] camera_capture_photo(requestId=%d) -> success\n", requestId);
    haskellOnCameraResult(ctx, requestId, CAMERA_SUCCESS, "/tmp/stub_photo.jpg");
}

static void stub_start_video(void *ctx, int32_t requestId)
{
    fprintf(stderr, "[CameraBridge stub] camera_start_video(requestId=%d) -> success\n", requestId);
    haskellOnCameraResult(ctx, requestId, CAMERA_SUCCESS, "/tmp/stub_video.mp4");
}

static void stub_stop_video(void)
{
    fprintf(stderr, "[CameraBridge stub] camera_stop_video() -> no-op\n");
}

/* ---- Public API ---- */

void camera_start_session(void *ctx, int32_t source)
{
    if (g_start_session_impl) {
        g_start_session_impl(ctx, source);
        return;
    }
    stub_start_session(ctx, source);
}

void camera_stop_session(void)
{
    if (g_stop_session_impl) {
        g_stop_session_impl();
        return;
    }
    stub_stop_session();
}

void camera_capture_photo(void *ctx, int32_t requestId)
{
    if (g_capture_photo_impl) {
        g_capture_photo_impl(ctx, requestId);
        return;
    }
    stub_capture_photo(ctx, requestId);
}

void camera_start_video(void *ctx, int32_t requestId)
{
    if (g_start_video_impl) {
        g_start_video_impl(ctx, requestId);
        return;
    }
    stub_start_video(ctx, requestId);
}

void camera_stop_video(void)
{
    if (g_stop_video_impl) {
        g_stop_video_impl();
        return;
    }
    stub_stop_video();
}
