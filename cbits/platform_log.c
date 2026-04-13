/*
 * Platform-aware logging for Hatter.
 *
 * Uses Android logcat, Apple os_log, or stderr depending on platform.
 * Called from Haskell via FFI to log lifecycle events and diagnostics.
 */

#ifdef __ANDROID__
#include <android/log.h>
#elif defined(__APPLE__)
#include <os/log.h>

/* Use a named subsystem so os_log messages appear in `log stream --level info`.
 * OS_LOG_DEFAULT with OS_LOG_TYPE_INFO may not be surfaced by log stream. */
static os_log_t haskell_log(void) {
    static os_log_t log = NULL;
    if (!log) {
        log = os_log_create("me.jappie.hatter", "Hatter");
    }
    return log;
}
#else
#include <stdio.h>
#endif

void hatterLog(const char *msg) {
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "Hatter", "%s", msg);
#elif defined(__APPLE__)
    os_log_with_type(haskell_log(), OS_LOG_TYPE_INFO, "%{public}s", msg);
#else
    fprintf(stderr, "[Hatter] %s\n", msg);
#endif
}
