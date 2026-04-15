/*
 * JNI bridge between Android Java and Haskell FFI exports.
 *
 * This file is compiled by NDK clang (not cabal), and linked into
 * libhatter.so alongside the Haskell static library.
 *
 * The Java package name is controlled by -DJNI_PACKAGE at compile time;
 * see include/JniBridge.h for defaults.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "HsFFI.h"
#include "JniBridge.h"
#include "PermissionBridge.h"
#include "SecureStorageBridge.h"
#include "BleBridge.h"
#include "DialogBridge.h"
#include "LocationBridge.h"
#include "AuthSessionBridge.h"
#include "CameraBridge.h"
#include "BottomSheetBridge.h"
#include "HttpBridge.h"
#include "NetworkStatusBridge.h"
#include "AnimationBridge.h"
#include "PlatformSignInBridge.h"

#ifdef DEBUG_OOM
#include <android/log.h>
#include <sys/mman.h>
#include <errno.h>
#include <dlfcn.h>
#include <unwind.h>

static void log_memory_status(const char *label) {
    FILE *f = fopen("/proc/self/status", "r");
    if (!f) return;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "VmSize:", 7) == 0 ||
            strncmp(line, "VmRSS:",  6) == 0 ||
            strncmp(line, "VmPeak:", 7) == 0) {
            /* trim newline */
            size_t len = strlen(line);
            if (len > 0 && line[len-1] == '\n') line[len-1] = '\0';
            __android_log_print(ANDROID_LOG_INFO, "HatterOOM",
                "%s: %s", label, line);
        }
    }
    fclose(f);
}

__attribute__((constructor(101)))
static void oom_debug_constructor(void) {
    log_memory_status("init_array");
}

/* registerForeignExports wrapper: log each ForeignExportsList registration.
 * This runs during .init_array processing (before hs_init) and reveals
 * whether any module has a corrupted n_entries field.
 * Linked via -Wl,--wrap=registerForeignExports
 *
 * GHC 9.x struct layout (flexible array member):
 *   struct ForeignExportsList {
 *     struct ForeignExportsList *next;
 *     int n_entries;
 *     StgClosure *exports[];   // flexible array member
 *   };
 */
struct ForeignExportsList {
    struct ForeignExportsList *next;
    int n_entries;
    void *exports[];
};

extern void __real_registerForeignExports(struct ForeignExportsList *exports);
static int g_fexport_list_count = 0;
static int g_fexport_total_entries = 0;

void __wrap_registerForeignExports(struct ForeignExportsList *exports) {
    g_fexport_list_count++;
    int n = exports ? exports->n_entries : -1;
    __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
        "registerForeignExports #%d: n_entries=%d next=%p struct_at=%p",
        g_fexport_list_count, n,
        exports ? (void*)exports->next : NULL,
        (void*)exports);
    if (exports && n > 0 && n < 10000) {
        g_fexport_total_entries += n;
        for (int i = 0; i < n && i < 5; i++) {
            __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
                "  export[%d] = %p", i, exports->exports[i]);
        }
    } else if (exports && n >= 10000) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "  SUSPICIOUS n_entries=%d (>= 10000)! Likely corrupted.", n);
    }
    __real_registerForeignExports(exports);
}

/* getStablePtr wrapper: count calls during hs_init.
 * If this fires millions of times, something is creating huge numbers
 * of stable pointers beyond the ~21 foreign exports.
 * Linked via -Wl,--wrap=getStablePtr */
extern void *__real_getStablePtr(void *p);
static volatile int g_stable_ptr_count = 0;

void *__wrap_getStablePtr(void *p) {
    g_stable_ptr_count++;
    /* Log every power-of-2 to avoid flooding logcat */
    if (g_stable_ptr_count <= 32 ||
        (g_stable_ptr_count & (g_stable_ptr_count - 1)) == 0) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "getStablePtr #%d: closure=%p",
            g_stable_ptr_count, p);
    }
    return __real_getStablePtr(p);
}

/* Stack unwinding for backtrace on ARM Android.
 * _Unwind_Backtrace is reliable on ARM (unlike __builtin_return_address(N>0))
 * because it uses .ARM.exidx unwind tables rather than frame pointers. */
struct BacktraceState {
    void **frames;
    int frame_count;
    int max_frames;
};

static _Unwind_Reason_Code unwind_callback(struct _Unwind_Context *context,
                                            void *arg) {
    struct BacktraceState *state = (struct BacktraceState *)arg;
    uintptr_t pc = _Unwind_GetIP(context);
    if (pc == 0) return _URC_END_OF_STACK;
    if (state->frame_count < state->max_frames) {
        state->frames[state->frame_count++] = (void *)pc;
    }
    return (state->frame_count >= state->max_frames)
        ? _URC_END_OF_STACK : _URC_NO_REASON;
}

static void log_backtrace(const char *label) {
    void *frames[16];
    struct BacktraceState state = { frames, 0, 16 };
    _Unwind_Backtrace(unwind_callback, &state);

    __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
        "%s backtrace (%d frames):", label, state.frame_count);
    for (int i = 0; i < state.frame_count; i++) {
        Dl_info info;
        if (dladdr(frames[i], &info) && info.dli_sname) {
            __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
                "  #%d: %s+0x%lx (%s)",
                i, info.dli_sname,
                (unsigned long)((char*)frames[i] - (char*)info.dli_saddr),
                info.dli_fname ? info.dli_fname : "???");
        } else if (dladdr(frames[i], &info)) {
            __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
                "  #%d: %p (offset 0x%lx in %s)",
                i, frames[i],
                (unsigned long)((char*)frames[i] - (char*)info.dli_fbase),
                info.dli_fname ? info.dli_fname : "???");
        } else {
            __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
                "  #%d: %p (unknown)", i, frames[i]);
        }
    }
}

/* stgMallocBytes wrapper: intercept GHC RTS allocations.
 * stgMallocBytes(size, msg) is GHC's universal malloc wrapper — every
 * RTS subsystem goes through it, and each call site passes a descriptive
 * string (e.g. "enlargeStablePtrTable", "initCapabilities").
 * This gives us the CALLER NAME without needing backtraces.
 * Linked via -Wl,--wrap=stgMallocBytes */
extern void *__real_stgMallocBytes(size_t n, char *msg);

void *__wrap_stgMallocBytes(size_t n, char *msg) {
    if (n >= 1 * 1024 * 1024) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "stgMallocBytes(%zu, \"%s\") = %zu MB",
            n, msg ? msg : "(null)", n / (1024*1024));
        log_memory_status("stgMallocBytes");
    }
    return __real_stgMallocBytes(n, msg);
}

/* stgReallocBytes wrapper: same idea for realloc-based RTS allocations.
 * Linked via -Wl,--wrap=stgReallocBytes */
extern void *__real_stgReallocBytes(void *p, size_t n, char *msg);

void *__wrap_stgReallocBytes(void *p, size_t n, char *msg) {
    if (n >= 1 * 1024 * 1024) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "stgReallocBytes(%p, %zu, \"%s\") = %zu MB",
            p, n, msg ? msg : "(null)", n / (1024*1024));
        log_memory_status("stgReallocBytes");
    }
    return __real_stgReallocBytes(p, n, msg);
}

/* malloc wrapper: catch any large malloc NOT going through stgMallocBytes.
 * Linked via -Wl,--wrap=malloc */
extern void *__real_malloc(size_t size);

void *__wrap_malloc(size_t size) {
    if (size >= 512 * 1024 * 1024) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "LARGE malloc(%zu) = %zu MB (not via stgMallocBytes)",
            size, size / (1024*1024));
        log_memory_status("large_malloc");
    }
    return __real_malloc(size);
}

/* realloc wrapper: catch any large realloc NOT going through stgReallocBytes.
 * Linked via -Wl,--wrap=realloc */
extern void *__real_realloc(void *ptr, size_t size);

void *__wrap_realloc(void *ptr, size_t size) {
    if (size >= 512 * 1024 * 1024) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "LARGE realloc(%p, %zu) = %zu MB (not via stgReallocBytes)",
            ptr, size, size / (1024*1024));
        log_memory_status("large_realloc");
    }
    return __real_realloc(ptr, size);
}

/* mmap/mmap64 wrapper: intercept large/failed mmaps during hs_init.
 *
 * On 32-bit Android, GHC RTS is compiled with _FILE_OFFSET_BITS=64
 * (via AC_SYS_LARGEFILE in configure.ac).  Bionic's <sys/mman.h>
 * then renames mmap() → mmap64 via __asm__ symbol renaming.
 * So the actual linker symbol in the RTS .a is "mmap64", not "mmap".
 *
 * We wrap BOTH to catch all callers:
 *   -Wl,--wrap=mmap   catches code compiled without LFS
 *   -Wl,--wrap=mmap64 catches GHC RTS and LFS-enabled code
 */
extern void *__real_mmap(void *addr, size_t length, int prot,
                         int flags, int fd, off_t offset);
extern void *__real_mmap64(void *addr, size_t length, int prot,
                           int flags, int fd, off64_t offset);

/* Track mmap activity during hs_init */
static volatile int g_tracking_hs_init = 0;
static volatile size_t g_mmap_total_bytes = 0;
static volatile int g_mmap_call_count = 0;
static volatile int g_mmap_fail_count = 0;

static void track_mmap(const char *variant, size_t length, int prot,
                       int flags, void *result, void *caller) {
    int mmap_errno = errno;

    g_mmap_call_count++;
    if (result != MAP_FAILED) {
        g_mmap_total_bytes += length;
    }

    /* Log any mmap >= 16 MB (suspicious on 32-bit) */
    if (length >= 16 * 1024 * 1024) {
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "LARGE %s(%zu) = %zu MB, prot=%d flags=0x%x "
            "caller=%p result=%p",
            variant, length, length / (1024*1024), prot, flags,
            caller, result);
    }

    /* Log any mmap failure */
    if (result == MAP_FAILED) {
        g_mmap_fail_count++;
        __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
            "FAILED %s(%zu) = %zu MB, prot=%d flags=0x%x "
            "caller=%p errno=%d (%s)",
            variant, length, length / (1024*1024), prot, flags,
            caller, mmap_errno, strerror(mmap_errno));
        log_memory_status("mmap_failed");
    }

    /* Periodic summary every 100 calls */
    if (g_mmap_call_count % 100 == 0) {
        __android_log_print(ANDROID_LOG_INFO, "HatterOOM",
            "mmap progress: %d calls, %zu MB mapped, %d failures",
            g_mmap_call_count,
            g_mmap_total_bytes / (1024*1024),
            g_mmap_fail_count);
    }
}

void *__wrap_mmap(void *addr, size_t length, int prot,
                  int flags, int fd, off_t offset) {
    int saved_errno = errno;
    void *result = __real_mmap(addr, length, prot, flags, fd, offset);
    if (g_tracking_hs_init) {
        track_mmap("mmap", length, prot, flags, result,
                   __builtin_return_address(0));
    }
    if (result != MAP_FAILED) errno = saved_errno;
    return result;
}

void *__wrap_mmap64(void *addr, size_t length, int prot,
                    int flags, int fd, off64_t offset) {
    int saved_errno = errno;
    void *result = __real_mmap64(addr, length, prot, flags, fd, offset);
    if (g_tracking_hs_init) {
        track_mmap("mmap64", length, prot, flags, result,
                   __builtin_return_address(0));
    }
    if (result != MAP_FAILED) errno = saved_errno;
    return result;
}
#endif /* DEBUG_OOM */

/* Runs the user's Haskell main via RTS API (cbits/run_main.c).
 * Returns the opaque AppContext pointer. */
extern void *haskellRunMain(void);

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (Hatter.Locale) */
extern void haskellLogLocale(void);

/* App files directory (cbits/files_dir.c) */
extern void setAppFilesDir(const char *path);

/* Haskell foreign exports */
extern void haskellOnLifecycle(void *ctx, int eventType);
extern void haskellRenderUI(void *ctx);
extern void haskellOnUIEvent(void *ctx, int callbackId);
extern void haskellOnUITextChange(void *ctx, int callbackId, const char *text);
extern void haskellOnPermissionResult(void *ctx, int32_t requestId, int32_t statusCode);
extern void haskellOnSecureStorageResult(void *ctx, int32_t requestId,
                                          int32_t statusCode, const char *value);
extern void haskellOnBleScanResult(void *ctx, const char *name, const char *address, int32_t rssi);
extern void haskellOnDialogResult(void *ctx, int32_t requestId, int32_t actionCode);
extern void haskellOnLocationUpdate(void *ctx, double lat, double lon, double alt, double acc);
extern void haskellOnAuthSessionResult(void *ctx, int32_t requestId,
                                        int32_t statusCode,
                                        const char *redirectUrl,
                                        const char *errorMessage);
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                   int32_t statusCode,
                                   const uint8_t *imageData, int32_t imageDataLen,
                                   int32_t width, int32_t height);
extern void haskellOnBottomSheetResult(void *ctx, int32_t requestId, int32_t actionCode);
extern void haskellOnHttpResult(void *ctx, int32_t requestId,
                                 int32_t resultCode, int32_t httpStatus,
                                 const char *headers,
                                 const char *body, int32_t bodyLen);
extern void haskellOnNetworkStatusChange(void *ctx, int connected, int transport);
extern void haskellOnAnimationFrame(void *ctx, double timestampMs);
extern void haskellOnPlatformSignInResult(void *ctx, int32_t requestId,
                                           int32_t statusCode,
                                           const char *identityToken,
                                           const char *userId,
                                           const char *email,
                                           const char *fullName,
                                           int32_t provider);

/* Android UI bridge (from ui_bridge_android.c) */
extern void setup_android_ui_bridge(JNIEnv *env, jobject activity, void *haskellCtx);
extern void android_handle_click(JNIEnv *env, jobject view, void *haskellCtx);
extern void android_handle_text_change(JNIEnv *env, jobject view, jstring text, void *haskellCtx);

/* Android permission bridge (from permission_bridge_android.c) */
extern void setup_android_permission_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android secure storage bridge (from secure_storage_android.c) */
extern void setup_android_secure_storage_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android BLE bridge (from ble_bridge_android.c) */
extern void setup_android_ble_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android dialog bridge (from dialog_bridge_android.c) */
extern void setup_android_dialog_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android location bridge (from location_bridge_android.c) */
extern void setup_android_location_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android auth session bridge (from auth_session_android.c) */
extern void setup_android_auth_session_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android camera bridge (from camera_bridge_android.c) */
extern void setup_android_camera_bridge(JNIEnv *env, jobject activity, void *haskellCtx);
/* Android bottom sheet bridge (from bottom_sheet_android.c) */
extern void setup_android_bottom_sheet_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android HTTP bridge (from http_bridge_android.c) */
extern void setup_android_http_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android network status bridge (from network_status_android.c) */
extern void setup_android_network_status_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android animation bridge (from animation_bridge_android.c) */
extern void setup_android_animation_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android platform sign-in bridge (from platform_sign_in_android.c) */
extern void setup_android_platform_sign_in_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Lifecycle event codes (must match Hatter.h) */
#define LIFECYCLE_CREATE     0
#define LIFECYCLE_START      1
#define LIFECYCLE_RESUME     2
#define LIFECYCLE_PAUSE      3
#define LIFECYCLE_STOP       4
#define LIFECYCLE_DESTROY    5
#define LIFECYCLE_LOW_MEMORY 6

/* Opaque Haskell context pointer, created during JNI_OnLoad */
static void *g_haskell_ctx = NULL;

JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM *vm, void *reserved)
{
#ifdef DEBUG_OOM
    log_memory_status("jni_onload_entry");
    __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
        "Before hs_init: %d ForeignExportsList registered, %d total entries, "
        "%d getStablePtr calls so far",
        g_fexport_list_count, g_fexport_total_entries, g_stable_ptr_count);
    g_tracking_hs_init = 1;
    g_mmap_total_bytes = 0;
    g_mmap_call_count = 0;
    g_mmap_fail_count = 0;
#endif
    hs_init(NULL, NULL);
#ifdef DEBUG_OOM
    g_tracking_hs_init = 0;
    __android_log_print(ANDROID_LOG_ERROR, "HatterOOM",
        "hs_init DONE: %d getStablePtr calls, %d mmap calls, "
        "%zu MB mapped, %d failures",
        g_stable_ptr_count,
        g_mmap_call_count,
        g_mmap_total_bytes / (1024*1024),
        g_mmap_fail_count);
    log_memory_status("after_hs_init");
#endif

    /* Pre-haskellRunMain platform init: set globals that Haskell code may
       read immediately (e.g. in startMobileApp callbacks). */
    {
        JNIEnv *env;
        (*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6);

        /* Locale: Locale.getDefault().toLanguageTag() (static, no context needed) */
        jclass localeClass = (*env)->FindClass(env, "java/util/Locale");
        jmethodID getDefault = (*env)->GetStaticMethodID(env, localeClass,
            "getDefault", "()Ljava/util/Locale;");
        jobject locale = (*env)->CallStaticObjectMethod(env, localeClass, getDefault);
        jmethodID toLanguageTag = (*env)->GetMethodID(env, localeClass,
            "toLanguageTag", "()Ljava/lang/String;");
        jstring jtag = (*env)->CallObjectMethod(env, locale, toLanguageTag);
        const char *ctag = (*env)->GetStringUTFChars(env, jtag, NULL);
        setSystemLocale(strdup(ctag));
        (*env)->ReleaseStringUTFChars(env, jtag, ctag);

        /* Files dir: ActivityThread.currentApplication().getFilesDir().
           The Application exists before any Activity, so this is available
           during JNI_OnLoad (called from System.loadLibrary). */
        jclass atClass = (*env)->FindClass(env, "android/app/ActivityThread");
        jmethodID currentApp = (*env)->GetStaticMethodID(env, atClass,
            "currentApplication", "()Landroid/app/Application;");
        jobject app = (*env)->CallStaticObjectMethod(env, atClass, currentApp);
        if (app) {
            jclass ctxClass = (*env)->FindClass(env, "android/content/Context");
            jmethodID getFilesDir = (*env)->GetMethodID(env, ctxClass,
                "getFilesDir", "()Ljava/io/File;");
            jobject filesDir = (*env)->CallObjectMethod(env, app, getFilesDir);
            if (filesDir) {
                jclass fileClass = (*env)->FindClass(env, "java/io/File");
                jmethodID getAbsPath = (*env)->GetMethodID(env, fileClass,
                    "getAbsolutePath", "()Ljava/lang/String;");
                jstring jpath = (*env)->CallObjectMethod(env, filesDir, getAbsPath);
                const char *cpath = (*env)->GetStringUTFChars(env, jpath, NULL);
                setAppFilesDir(strdup(cpath));
                (*env)->ReleaseStringUTFChars(env, jpath, cpath);
            }
        }
    }

#ifdef DEBUG_OOM
    log_memory_status("after_platform_init");
#endif
    g_haskell_ctx = haskellRunMain();
#ifdef DEBUG_OOM
    log_memory_status("after_haskell_run_main");
#endif
    haskellLogLocale();

    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
JNI_OnUnload(JavaVM *vm, void *reserved)
{
    hs_exit();
}

/* --- UI bridge JNI methods --- */

JNIEXPORT void JNICALL
JNI_METHOD(renderUI)(JNIEnv *env, jobject thiz)
{
    setup_android_ui_bridge(env, thiz, g_haskell_ctx);
    setup_android_permission_bridge(env, thiz, g_haskell_ctx);
    setup_android_secure_storage_bridge(env, thiz, g_haskell_ctx);
    setup_android_ble_bridge(env, thiz, g_haskell_ctx);
    setup_android_dialog_bridge(env, thiz, g_haskell_ctx);
    setup_android_location_bridge(env, thiz, g_haskell_ctx);
    setup_android_auth_session_bridge(env, thiz, g_haskell_ctx);
    setup_android_camera_bridge(env, thiz, g_haskell_ctx);
    setup_android_bottom_sheet_bridge(env, thiz, g_haskell_ctx);
    setup_android_http_bridge(env, thiz, g_haskell_ctx);
    setup_android_network_status_bridge(env, thiz, g_haskell_ctx);
    setup_android_animation_bridge(env, thiz, g_haskell_ctx);
    setup_android_platform_sign_in_bridge(env, thiz, g_haskell_ctx);
    haskellRenderUI(g_haskell_ctx);
}

JNIEXPORT void JNICALL
JNI_METHOD(onButtonClick)(JNIEnv *env, jobject thiz, jobject view)
{
    android_handle_click(env, view, g_haskell_ctx);
}

JNIEXPORT void JNICALL
JNI_METHOD(onTextChange)(JNIEnv *env, jobject thiz, jobject view, jstring text)
{
    android_handle_text_change(env, view, text, g_haskell_ctx);
}

/* Lifecycle JNI callbacks */
JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleCreate)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_CREATE);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleStart)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_START);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleResume)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_RESUME);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecyclePause)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_PAUSE);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleStop)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_STOP);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleDestroy)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_DESTROY);
}

JNIEXPORT void JNICALL
JNI_METHOD(onLifecycleLowMemory)(JNIEnv *env, jobject thiz)
{
    haskellOnLifecycle(g_haskell_ctx, LIFECYCLE_LOW_MEMORY);
}
