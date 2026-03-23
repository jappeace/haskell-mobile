#ifndef HASKELL_MOBILE_H
#define HASKELL_MOBILE_H

/* GHC RTS initialization (call before any Haskell function) */
void hs_init(int *argc, char **argv[]);

/* Haskell FFI exports */
void haskellInit(void);
char *haskellGreet(const char *name);

/* Create a default mobile context. Returns an opaque pointer.
 * Call after haskellInit(). */
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

#endif /* HASKELL_MOBILE_H */
