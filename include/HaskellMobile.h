#ifndef HASKELL_MOBILE_H
#define HASKELL_MOBILE_H

#include <stdint.h>

/* GHC RTS initialization (call before any Haskell function) */
void hs_init(int *argc, char **argv[]);

/* Haskell FFI exports */
char *haskellGreet(const char *name);

/* Run the user's Haskell main :: IO (Ptr AppContext).
 * Uses the GHC RTS API to evaluate ZCMain_main_closure and capture
 * the returned context pointer — no foreign export ccall needed in
 * the user's Main.hs.
 * Call after hs_init(). Returns an opaque pointer to be passed to
 * all subsequent haskell* calls. */
void *haskellRunMain(void);

/* Platform-aware logging (Android logcat / Apple os_log / stderr) */
void haskellMobileLog(const char *msg);

/* Lifecycle event codes */
#define LIFECYCLE_CREATE     0
#define LIFECYCLE_START      1
#define LIFECYCLE_RESUME     2
#define LIFECYCLE_PAUSE      3
#define LIFECYCLE_STOP       4
#define LIFECYCLE_DESTROY    5
#define LIFECYCLE_LOW_MEMORY 6

/* Notify Haskell of a lifecycle event. Unknown codes are silently ignored.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnLifecycle(void *ctx, int eventType);

/* Render the UI tree. Calls appView to get the widget description,
 * then issues ui_* calls through the registered bridge callbacks.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellRenderUI(void *ctx);

/* Dispatch a UI event (e.g. button click). Fires the callback
 * registered for the given callbackId, then re-renders.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnUIEvent(void *ctx, int32_t callbackId);

/* Dispatch a text change event. Fires the text-change callback
 * registered for the given callbackId with the new text value.
 * Does NOT re-render (avoids cursor/flicker issues).
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnUITextChange(void *ctx, int32_t callbackId, const char *text);


/* Log the detected system locale via platformLog.
 * Called from platform bridges after setSystemLocale(). */
void haskellLogLocale(void);

/* Set the system locale string. Called by platform bridges during init.
 * The caller owns the memory (must be static or strdup'd). */
void setSystemLocale(const char *locale);

/* Get the system locale string. Returns the value set by setSystemLocale(),
 * or falls back to LANG env var (desktop) or "en" (default). */
const char* getSystemLocale(void);

/* Dispatch a permission result from native code back to Haskell.
 * requestId: opaque ID from the original permission_request() call.
 * statusCode: PERMISSION_GRANTED (0) or PERMISSION_DENIED (1).
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnPermissionResult(void *ctx, int32_t requestId, int32_t statusCode);

/* Dispatch a secure storage result from native code back to Haskell.
 * requestId: opaque ID from the original secure_storage_*() call.
 * statusCode: SECURE_STORAGE_SUCCESS (0), SECURE_STORAGE_NOT_FOUND (1),
 *             or SECURE_STORAGE_ERROR (2).
 * value:     null-terminated value string for read results, or NULL.
 * ctx must be a pointer returned by haskellCreateContext(). */
void haskellOnSecureStorageResult(void *ctx, int32_t requestId,
                                   int32_t statusCode, const char *value);

/* Dispatch a BLE scan result from native code back to Haskell.
 * name: device name (may be NULL for unnamed devices).
 * address: device address string.
 * rssi: received signal strength indicator.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnBleScanResult(void *ctx, const char *name, const char *address, int32_t rssi);

/* Dialog action codes */
#define DIALOG_BUTTON_1   0
#define DIALOG_BUTTON_2   1
#define DIALOG_BUTTON_3   2
#define DIALOG_DISMISSED  3

/* Dispatch a dialog result from native code back to Haskell.
 * requestId:  opaque ID from the original dialog_show() call.
 * actionCode: DIALOG_BUTTON_1 (0), DIALOG_BUTTON_2 (1),
 *             DIALOG_BUTTON_3 (2), or DIALOG_DISMISSED (3).
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnDialogResult(void *ctx, int32_t requestId, int32_t actionCode);

/* Dispatch a location update from native code back to Haskell.
 * lat: latitude in degrees.
 * lon: longitude in degrees.
 * alt: altitude in metres above sea level.
 * acc: horizontal accuracy in metres.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnLocationUpdate(void *ctx, double lat, double lon, double alt, double acc);

/* Auth session status codes */
#define AUTH_SESSION_SUCCESS    0
#define AUTH_SESSION_CANCELLED  1
#define AUTH_SESSION_ERROR      2

/* Dispatch an auth session result from native code back to Haskell.
 * requestId:   opaque ID from the original auth_session_start() call.
 * statusCode:  AUTH_SESSION_SUCCESS (0), AUTH_SESSION_CANCELLED (1),
 *              or AUTH_SESSION_ERROR (2).
 * redirectUrl: null-terminated redirect URL string for success, or NULL.
 * errorMessage: null-terminated error message for errors, or NULL.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnAuthSessionResult(void *ctx, int32_t requestId,
                                 int32_t statusCode,
                                 const char *redirectUrl,
                                 const char *errorMessage);

/* Camera status codes */
#define CAMERA_SUCCESS           0
#define CAMERA_CANCELLED         1
#define CAMERA_PERMISSION_DENIED 2
#define CAMERA_UNAVAILABLE       3
#define CAMERA_ERROR             4

/* Dispatch a camera result from native code back to Haskell.
 * requestId:    opaque ID from the original camera capture call.
 * statusCode:   CAMERA_SUCCESS (0), CAMERA_CANCELLED (1),
 *               CAMERA_PERMISSION_DENIED (2), CAMERA_UNAVAILABLE (3),
 *               or CAMERA_ERROR (4).
 * imageData:    JPEG-encoded image bytes, or NULL.
 * imageDataLen: length of imageData in bytes, or 0.
 * width:        image width in pixels, or 0.
 * height:       image height in pixels, or 0.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnCameraResult(void *ctx, int32_t requestId,
                            int32_t statusCode,
                            const uint8_t *imageData, int32_t imageDataLen,
                            int32_t width, int32_t height);

/* Dispatch a video frame from native code back to Haskell.
 * requestId:    opaque ID from the startVideoCapture call.
 * frameData:    JPEG-encoded frame bytes.
 * frameDataLen: length of frameData in bytes.
 * width:        frame width in pixels.
 * height:       frame height in pixels.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnVideoFrame(void *ctx, int32_t requestId,
                          const uint8_t *frameData, int32_t frameDataLen,
                          int32_t width, int32_t height);

/* Dispatch an audio chunk from native code back to Haskell.
 * requestId:    opaque ID from the startVideoCapture call.
 * audioData:    raw PCM audio bytes.
 * audioDataLen: length of audioData in bytes.
 * ctx must be a pointer returned by haskellRunMain(). */
void haskellOnAudioChunk(void *ctx, int32_t requestId,
                          const uint8_t *audioData, int32_t audioDataLen);

#endif /* HASKELL_MOBILE_H */
