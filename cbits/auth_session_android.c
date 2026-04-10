/*
 * Android implementation of the auth session bridge callback.
 *
 * Uses JNI to call Activity.startAuthSession(requestId, url, scheme)
 * which opens the system browser via Intent.ACTION_VIEW.
 * The redirect arrives via onNewIntent() and calls back through
 * onAuthSessionResult JNI callback.
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread — the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "AuthSessionBridge.h"
#include "JniBridge.h"

#define LOG_TAG "AuthSessionBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnAuthSessionResult(void *ctx, int32_t requestId,
                                        int32_t statusCode,
                                        const char *redirectUrl,
                                        const char *errorMessage);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env         = NULL;
static jobject  g_activity     = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx  = NULL;

/* Cached JNI method ID */
static jmethodID g_method_startAuthSession;

/* ---- Auth session bridge implementation ---- */

static void android_auth_session_start(void *ctx, int32_t requestId,
                                        const char *authUrl,
                                        const char *callbackScheme)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("auth_session_start: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    jstring jUrl = (*env)->NewStringUTF(env, authUrl);
    jstring jScheme = (*env)->NewStringUTF(env, callbackScheme);
    LOGI("auth_session_start(url=\"%s\", scheme=\"%s\", id=%d)",
         authUrl, callbackScheme, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_startAuthSession,
                           (jint)requestId, jUrl, jScheme);
    (*env)->DeleteLocalRef(env, jUrl);
    (*env)->DeleteLocalRef(env, jScheme);
}

/* ---- Public API ---- */

/*
 * Set up the Android auth session bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callback with the
 * platform-agnostic dispatcher.
 */
void setup_android_auth_session_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_startAuthSession = (*env)->GetMethodID(env, actClass,
        "startAuthSession", "(ILjava/lang/String;Ljava/lang/String;)V");

    if (!g_method_startAuthSession) {
        LOGE("Failed to resolve startAuthSession JNI method ID — bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    auth_session_register_impl(android_auth_session_start);

    LOGI("Android auth session bridge initialized");
}

/* ---- JNI callback from Java ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onAuthSessionResult)(JNIEnv *env, jobject thiz,
                                 jint requestId, jint statusCode,
                                 jstring redirectUrl, jstring errorMsg)
{
    g_env = env;
    const char *cRedirectUrl = NULL;
    const char *cErrorMsg = NULL;

    if (redirectUrl != NULL) {
        cRedirectUrl = (*env)->GetStringUTFChars(env, redirectUrl, NULL);
    }
    if (errorMsg != NULL) {
        cErrorMsg = (*env)->GetStringUTFChars(env, errorMsg, NULL);
    }

    LOGI("onAuthSessionResult(requestId=%d, statusCode=%d, url=%s, err=%s)",
         requestId, statusCode,
         cRedirectUrl ? cRedirectUrl : "NULL",
         cErrorMsg ? cErrorMsg : "NULL");

    haskellOnAuthSessionResult(g_haskell_ctx, (int32_t)requestId,
                                (int32_t)statusCode, cRedirectUrl, cErrorMsg);

    if (cRedirectUrl != NULL) {
        (*env)->ReleaseStringUTFChars(env, redirectUrl, cRedirectUrl);
    }
    if (cErrorMsg != NULL) {
        (*env)->ReleaseStringUTFChars(env, errorMsg, cErrorMsg);
    }
}
