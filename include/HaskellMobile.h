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

#endif /* HASKELL_MOBILE_H */
