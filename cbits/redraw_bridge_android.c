/*
 * Android implementation of the redraw bridge.
 *
 * Uses JNI to call Activity.requestRedraw(), which runs
 * renderUI() on the main/UI thread via runOnUiThread().
 * Compiled by NDK clang, not cabal.
 *
 * request_redraw() may be called from any thread (e.g. a Haskell
 * background thread doing network sync). The Java side ensures
 * the actual rendering happens on the UI thread.
 */

#include <jni.h>
#include <android/log.h>
#include "RedrawBridge.h"
#include "JniBridge.h"

#define LOG_TAG "RedrawBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* ---- Global state (set on the UI thread during setup) ---- */
static JavaVM   *g_jvm          = NULL;   /* cached JVM for attaching threads */
static jobject   g_activity     = NULL;   /* global ref to Activity */
static jmethodID g_method_requestRedraw;

/* ---- Redraw bridge implementation ---- */

static void android_request_redraw(void *ctx)
{
    JNIEnv *env = NULL;
    int need_detach = 0;

    if (!g_jvm || !g_activity) {
        LOGE("request_redraw: bridge not initialized");
        return;
    }

    /* Get JNIEnv for the current thread.
     * Background threads are not attached to the JVM, so we must
     * attach them temporarily. */
    jint status = (*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != JNI_OK) {
            LOGE("request_redraw: AttachCurrentThread failed");
            return;
        }
        need_detach = 1;
    } else if (status != JNI_OK) {
        LOGE("request_redraw: GetEnv failed (status=%d)", status);
        return;
    }

    LOGI("request_redraw()");
    (*env)->CallVoidMethod(env, g_activity, g_method_requestRedraw);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("request_redraw: Java exception thrown");
        (*env)->ExceptionClear(env);
    }

    if (need_detach) {
        (*g_jvm)->DetachCurrentThread(g_jvm);
    }
}

/* ---- Public API ---- */

/*
 * Set up the Android redraw bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callback with the
 * platform-agnostic dispatcher.
 */
void setup_android_redraw_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    /* Cache the JavaVM so background threads can get a JNIEnv */
    if (!g_jvm) {
        (*env)->GetJavaVM(env, &g_jvm);
    }

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_requestRedraw = (*env)->GetMethodID(env, actClass,
        "requestRedraw", "()V");

    /* Clean up local reference */
    (*env)->DeleteLocalRef(env, actClass);

    if (!g_method_requestRedraw) {
        LOGE("Failed to resolve requestRedraw JNI method ID — redraw bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    /* Clear any unexpected pending exception before continuing */
    if ((*env)->ExceptionCheck(env)) {
        LOGE("Unexpected JNI exception after redraw method resolution");
        (*env)->ExceptionClear(env);
    }

    redraw_register_impl(android_request_redraw);

    LOGI("Android redraw bridge initialized");
}
