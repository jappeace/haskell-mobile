/*
 * Android implementation of the animation frame loop bridge.
 *
 * Uses JNI to call Activity.startAnimationLoop() and
 * Activity.stopAnimationLoop(). Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread, the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "AnimationBridge.h"
#include "JniBridge.h"

#define LOG_TAG "AnimationBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches animation frame back to Haskell) */
extern void haskellOnAnimationFrame(void *ctx, double timestampMs);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env          = NULL;
static jobject  g_activity      = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx   = NULL;   /* stored for async JNI callback */

/* Cached JNI method IDs */
static jmethodID g_method_startAnimationLoop;
static jmethodID g_method_stopAnimationLoop;

/* ---- Animation bridge implementations ---- */

static void android_animation_start_loop(void *ctx)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("animation_start_loop: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;
    LOGI("animation_start_loop()");
    (*env)->CallVoidMethod(env, g_activity, g_method_startAnimationLoop);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("animation_start_loop: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_animation_stop_loop(void)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("animation_stop_loop: bridge not initialized");
        return;
    }

    LOGI("animation_stop_loop()");
    (*env)->CallVoidMethod(env, g_activity, g_method_stopAnimationLoop);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("animation_stop_loop: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

/* ---- Public API ---- */

/*
 * Set up the Android animation bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callbacks with the
 * platform-agnostic dispatcher.
 */
void setup_android_animation_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_startAnimationLoop = (*env)->GetMethodID(env, actClass,
        "startAnimationLoop", "()V");
    g_method_stopAnimationLoop = (*env)->GetMethodID(env, actClass,
        "stopAnimationLoop", "()V");

    /* Clean up local reference */
    (*env)->DeleteLocalRef(env, actClass);

    if (!g_method_startAnimationLoop || !g_method_stopAnimationLoop) {
        LOGE("Failed to resolve animation JNI method IDs — animation bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    /* Clear any unexpected pending exception before continuing */
    if ((*env)->ExceptionCheck(env)) {
        LOGE("Unexpected JNI exception after animation method resolution");
        (*env)->ExceptionClear(env);
    }

    animation_register_impl(android_animation_start_loop,
                             android_animation_stop_loop);

    LOGI("Android animation bridge initialized");
}

/* ---- JNI callback from Java animation frame ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onAnimationFrame)(JNIEnv *env, jobject thiz,
                              jdouble timestampMs)
{
    g_env = env;
    haskellOnAnimationFrame(g_haskell_ctx, (double)timestampMs);
}
