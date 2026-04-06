#ifndef HASKELL_MOBILE_H
#define HASKELL_MOBILE_H

#include <stdint.h>

/* GHC RTS initialization (call before any Haskell function) */
void hs_init(int *argc, char **argv[]);

/* Haskell FFI exports */
char *haskellGreet(const char *name);

/* Run the user's Haskell main :: IO ().
 * Uses the GHC RTS API to evaluate ZCMain_main_closure — no
 * foreign export ccall needed in the user's Main.hs.
 * The user's main must call runMobileApp to register their app.
 * Call after hs_init(). */
void haskellRunMain(void);

/* Create a mobile context from the registered app. Returns an opaque pointer.
 * Call after haskellRunMain(). */
void *haskellCreateContext(void);

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
 * ctx must be a pointer returned by haskellCreateContext(). */
void haskellOnLifecycle(void *ctx, int eventType);

/* Render the UI tree. Calls appView to get the widget description,
 * then issues ui_* calls through the registered bridge callbacks.
 * ctx must be a pointer returned by haskellCreateContext(). */
void haskellRenderUI(void *ctx);

/* Dispatch a UI event (e.g. button click). Fires the callback
 * registered for the given callbackId, then re-renders.
 * ctx must be a pointer returned by haskellCreateContext(). */
void haskellOnUIEvent(void *ctx, int32_t callbackId);


/* Log the detected system locale via platformLog.
 * Called from platform bridges after setSystemLocale(). */
void haskellLogLocale(void);

/* Set the system locale string. Called by platform bridges during init.
 * The caller owns the memory (must be static or strdup'd). */
void setSystemLocale(const char *locale);

/* Get the system locale string. Returns the value set by setSystemLocale(),
 * or falls back to LANG env var (desktop) or "en" (default). */
const char* getSystemLocale(void);

#endif /* HASKELL_MOBILE_H */
