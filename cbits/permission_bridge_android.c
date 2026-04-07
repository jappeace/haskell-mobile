/*
 * Android implementation of the permission bridge callbacks.
 *
 * Uses JNI to call Activity.requestPermission() and Activity.checkPermission().
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread — the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "PermissionBridge.h"
#include "JniBridge.h"

#define LOG_TAG "PermissionBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnPermissionResult(void *ctx, int32_t requestId, int32_t statusCode);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env          = NULL;
static jobject  g_activity      = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx   = NULL;

/* Cached JNI method IDs */
static jmethodID g_method_requestPermission;
static jmethodID g_method_checkPermission;

/* ---- Permission bridge implementations ---- */

static void android_permission_request(int32_t permissionCode, int32_t requestId)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("permission_request: bridge not initialized");
        return;
    }

    LOGI("permission_request(code=%d, id=%d)", permissionCode, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_requestPermission,
                           (jint)permissionCode, (jint)requestId);
}

static int32_t android_permission_check(int32_t permissionCode)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("permission_check: bridge not initialized");
        return PERMISSION_DENIED;
    }

    jint result = (*env)->CallIntMethod(env, g_activity, g_method_checkPermission,
                                        (jint)permissionCode);
    LOGI("permission_check(code=%d) -> %d", permissionCode, result);
    return (int32_t)result;
}

/* ---- Public API ---- */

/*
 * Set up the Android permission bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callbacks with the
 * platform-agnostic dispatcher.
 */
void setup_android_permission_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_requestPermission = (*env)->GetMethodID(env, actClass,
        "requestPermission", "(II)V");
    g_method_checkPermission = (*env)->GetMethodID(env, actClass,
        "checkPermission", "(I)I");

    if (!g_method_requestPermission || !g_method_checkPermission) {
        LOGE("Failed to resolve permission JNI method IDs");
        return;
    }

    permission_register_impl(android_permission_request, android_permission_check);
    permission_set_context(haskellCtx);

    LOGI("Android permission bridge initialized");
}

/* ---- JNI callback from Java onRequestPermissionsResult ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onPermissionResult)(JNIEnv *env, jobject thiz, jint requestId, jint statusCode)
{
    g_env = env;
    LOGI("onPermissionResult(requestId=%d, statusCode=%d)", requestId, statusCode);
    haskellOnPermissionResult(g_haskell_ctx, (int32_t)requestId, (int32_t)statusCode);
}
