#ifndef CAMERA_BRIDGE_H
#define CAMERA_BRIDGE_H

#include <stdint.h>

/* Camera status codes (must match HaskellMobile.Camera) */
#define CAMERA_SUCCESS           0
#define CAMERA_CANCELLED         1
#define CAMERA_PERMISSION_DENIED 2
#define CAMERA_UNAVAILABLE       3
#define CAMERA_ERROR             4

/* Camera source codes */
#define CAMERA_SOURCE_BACK  0
#define CAMERA_SOURCE_FRONT 1

/*
 * Platform-agnostic camera bridge.
 *
 * Haskell calls camera_start_session/stop_session/capture_photo/
 * start_video/stop_video through these wrappers.  When no platform
 * callbacks are registered (desktop), start_session is a no-op,
 * capture_photo dispatches a success result with a dummy file path,
 * and start_video dispatches a success result with a dummy video path.
 *
 * On Android/iOS the platform-specific setup function fills in real
 * implementations via camera_register_impl().
 */

/* Start a camera session for the given source (back=0, front=1).
 * ctx: opaque Haskell context pointer (passed through to callback). */
void camera_start_session(void *ctx, int32_t source);

/* Stop the active camera session. */
void camera_stop_session(void);

/* Capture a photo.  Result is dispatched via haskellOnCameraResult().
 * ctx:       opaque Haskell context pointer.
 * requestId: opaque ID from Haskell (used to dispatch the result). */
void camera_capture_photo(void *ctx, int32_t requestId);

/* Start recording video.  Result is dispatched via haskellOnCameraResult()
 * when recording is stopped.
 * ctx:       opaque Haskell context pointer.
 * requestId: opaque ID from Haskell (used to dispatch the result). */
void camera_start_video(void *ctx, int32_t requestId);

/* Stop recording video.  The result callback registered by
 * camera_start_video is fired with the video file path. */
void camera_stop_video(void);

/* Register platform-specific implementations.
 * Called by platform setup functions (setup_android_camera_bridge, etc). */
void camera_register_impl(
    void (*start_session_impl)(void *, int32_t),
    void (*stop_session_impl)(void),
    void (*capture_photo_impl)(void *, int32_t),
    void (*start_video_impl)(void *, int32_t),
    void (*stop_video_impl)(void));

#endif /* CAMERA_BRIDGE_H */
