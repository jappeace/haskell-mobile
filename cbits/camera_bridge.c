/*
 * Platform-agnostic camera bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS).
 * Each camera_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), capture_photo dispatches
 * a success result with dummy JPEG bytes,
 * and start_video dispatches fake frames and a success completion
 * so that cabal test can verify the callback path.
 *
 * The opaque Haskell context pointer is threaded through each call
 * rather than stored as a global, allowing multiple contexts to coexist.
 */

#include "CameraBridge.h"
#include <stdio.h>

/* Haskell FFI exports (called from desktop stub to dispatch results back) */
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                   int32_t statusCode,
                                   const uint8_t *imageData, int32_t imageDataLen,
                                   int32_t width, int32_t height);
extern void haskellOnVideoFrame(void *ctx, int32_t requestId,
                                 const uint8_t *frameData, int32_t frameDataLen,
                                 int32_t width, int32_t height);
extern void haskellOnAudioChunk(void *ctx, int32_t requestId,
                                 const uint8_t *audioData, int32_t audioDataLen);

/* Minimal JPEG: SOI + EOI markers */
static const uint8_t stub_jpeg[] = { 0xFF, 0xD8, 0xFF, 0xD9 };

/* Fake PCM audio chunk (4 bytes of silence) */
static const uint8_t stub_audio[] = { 0x00, 0x00, 0x00, 0x00 };

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
    haskellOnCameraResult(ctx, requestId, CAMERA_SUCCESS,
                           stub_jpeg, (int32_t)sizeof(stub_jpeg), 1, 1);
}

static void stub_start_video(void *ctx, int32_t requestId)
{
    fprintf(stderr, "[CameraBridge stub] camera_start_video(requestId=%d) -> success\n", requestId);
    /* Fire a couple of fake video frames and an audio chunk so that
     * desktop tests can verify the push callbacks work. */
    haskellOnVideoFrame(ctx, requestId, stub_jpeg, (int32_t)sizeof(stub_jpeg), 1, 1);
    haskellOnVideoFrame(ctx, requestId, stub_jpeg, (int32_t)sizeof(stub_jpeg), 1, 1);
    haskellOnAudioChunk(ctx, requestId, stub_audio, (int32_t)sizeof(stub_audio));
    /* Completion: no picture data for video results */
    haskellOnCameraResult(ctx, requestId, CAMERA_SUCCESS,
                           NULL, 0, 0, 0);
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
