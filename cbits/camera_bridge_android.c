/*
 * Android implementation of the camera bridge callbacks.
 *
 * Uses JNI to call Activity.startCameraSession(),
 * Activity.stopCameraSession(), Activity.capturePhoto(),
 * Activity.startVideoCapture(), and Activity.stopVideoCapture().
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread, the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "CameraBridge.h"
#include "JniBridge.h"

#define LOG_TAG "CameraBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches camera result back to Haskell callback) */
extern void haskellOnCameraResult(void *ctx, int32_t requestId,
                                    int32_t statusCode, const char *filePath);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env          = NULL;
static jobject  g_activity      = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx   = NULL;   /* stored for async JNI callback */

/* Cached JNI method IDs */
static jmethodID g_method_startCameraSession;
static jmethodID g_method_stopCameraSession;
static jmethodID g_method_capturePhoto;
static jmethodID g_method_startVideoCapture;
static jmethodID g_method_stopVideoCapture;

/* ---- Camera bridge implementations ---- */

static void android_camera_start_session(void *ctx, int32_t source)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("camera_start_session: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;
    LOGI("camera_start_session(source=%d)", source);
    (*env)->CallVoidMethod(env, g_activity, g_method_startCameraSession, (jint)source);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("camera_start_session: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_camera_stop_session(void)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("camera_stop_session: bridge not initialized");
        return;
    }

    LOGI("camera_stop_session()");
    (*env)->CallVoidMethod(env, g_activity, g_method_stopCameraSession);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("camera_stop_session: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_camera_capture_photo(void *ctx, int32_t requestId)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("camera_capture_photo: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;
    LOGI("camera_capture_photo(requestId=%d)", requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_capturePhoto, (jint)requestId);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("camera_capture_photo: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_camera_start_video(void *ctx, int32_t requestId)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("camera_start_video: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;
    LOGI("camera_start_video(requestId=%d)", requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_startVideoCapture, (jint)requestId);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("camera_start_video: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_camera_stop_video(void)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("camera_stop_video: bridge not initialized");
        return;
    }

    LOGI("camera_stop_video()");
    (*env)->CallVoidMethod(env, g_activity, g_method_stopVideoCapture);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("camera_stop_video: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

/* ---- Public API ---- */

/*
 * Set up the Android camera bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callbacks with the
 * platform-agnostic dispatcher.
 */
void setup_android_camera_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_startCameraSession = (*env)->GetMethodID(env, actClass,
        "startCameraSession", "(I)V");
    g_method_stopCameraSession = (*env)->GetMethodID(env, actClass,
        "stopCameraSession", "()V");
    g_method_capturePhoto = (*env)->GetMethodID(env, actClass,
        "capturePhoto", "(I)V");
    g_method_startVideoCapture = (*env)->GetMethodID(env, actClass,
        "startVideoCapture", "(I)V");
    g_method_stopVideoCapture = (*env)->GetMethodID(env, actClass,
        "stopVideoCapture", "()V");

    /* Clean up local reference */
    (*env)->DeleteLocalRef(env, actClass);

    if (!g_method_startCameraSession || !g_method_stopCameraSession ||
        !g_method_capturePhoto || !g_method_startVideoCapture ||
        !g_method_stopVideoCapture) {
        LOGE("Failed to resolve camera JNI method IDs — camera bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    /* Clear any unexpected pending exception before continuing */
    if ((*env)->ExceptionCheck(env)) {
        LOGE("Unexpected JNI exception after camera method resolution");
        (*env)->ExceptionClear(env);
    }

    camera_register_impl(android_camera_start_session,
                          android_camera_stop_session,
                          android_camera_capture_photo,
                          android_camera_start_video,
                          android_camera_stop_video);

    LOGI("Android camera bridge initialized");
}

/* ---- JNI callback from Java camera result ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onCameraResult)(JNIEnv *env, jobject thiz,
                            jint requestId, jint statusCode,
                            jstring filePath)
{
    g_env = env;
    const char *cpath = NULL;
    if (filePath) {
        cpath = (*env)->GetStringUTFChars(env, filePath, NULL);
    }

    LOGI("onCameraResult(requestId=%d, status=%d, path=%s)",
         requestId, statusCode, cpath ? cpath : "null");
    haskellOnCameraResult(g_haskell_ctx, (int32_t)requestId,
                           (int32_t)statusCode, cpath);

    if (cpath) {
        (*env)->ReleaseStringUTFChars(env, filePath, cpath);
    }
}
