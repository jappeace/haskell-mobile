/*
 * Android implementation of the platform sign-in bridge.
 *
 * Uses JNI to call Activity.startPlatformSignIn(requestId, provider)
 * which uses AccountManager for Google sign-in or returns an error
 * for Apple sign-in.
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread -- the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "PlatformSignInBridge.h"
#include "JniBridge.h"

#define LOG_TAG "PlatformSignInBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnPlatformSignInResult(void *ctx, int32_t requestId,
                                           int32_t statusCode,
                                           const char *identityToken,
                                           const char *userId,
                                           const char *email,
                                           const char *fullName,
                                           int32_t provider);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env         = NULL;
static jobject  g_activity     = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx  = NULL;

/* Cached JNI method ID */
static jmethodID g_method_startPlatformSignIn;

/* ---- Platform sign-in bridge implementation ---- */

static void android_platform_sign_in_start(void *ctx, int32_t requestId,
                                            int32_t provider)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("platform_sign_in_start: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    LOGI("platform_sign_in_start(provider=%d, id=%d)", provider, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_startPlatformSignIn,
                           (jint)requestId, (jint)provider);
}

/* ---- Public API ---- */

/*
 * Set up the Android platform sign-in bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callback with the
 * platform-agnostic dispatcher.
 */
void setup_android_platform_sign_in_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_startPlatformSignIn = (*env)->GetMethodID(env, actClass,
        "startPlatformSignIn", "(II)V");

    if (!g_method_startPlatformSignIn) {
        LOGE("Failed to resolve startPlatformSignIn JNI method ID -- bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    platform_sign_in_register_impl(android_platform_sign_in_start);

    LOGI("Android platform sign-in bridge initialized");
}

/* ---- JNI callback from Java ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onPlatformSignInResult)(JNIEnv *env, jobject thiz,
                                    jint requestId, jint statusCode,
                                    jstring identityToken, jstring userId,
                                    jstring email, jstring fullName,
                                    jint provider)
{
    g_env = env;
    const char *cToken    = NULL;
    const char *cUserId   = NULL;
    const char *cEmail    = NULL;
    const char *cFullName = NULL;

    if (identityToken != NULL) {
        cToken = (*env)->GetStringUTFChars(env, identityToken, NULL);
    }
    if (userId != NULL) {
        cUserId = (*env)->GetStringUTFChars(env, userId, NULL);
    }
    if (email != NULL) {
        cEmail = (*env)->GetStringUTFChars(env, email, NULL);
    }
    if (fullName != NULL) {
        cFullName = (*env)->GetStringUTFChars(env, fullName, NULL);
    }

    LOGI("onPlatformSignInResult(requestId=%d, statusCode=%d, userId=%s, provider=%d)",
         requestId, statusCode,
         cUserId ? cUserId : "NULL",
         provider);

    haskellOnPlatformSignInResult(g_haskell_ctx, (int32_t)requestId,
                                   (int32_t)statusCode, cToken, cUserId,
                                   cEmail, cFullName, (int32_t)provider);

    if (cToken != NULL) {
        (*env)->ReleaseStringUTFChars(env, identityToken, cToken);
    }
    if (cUserId != NULL) {
        (*env)->ReleaseStringUTFChars(env, userId, cUserId);
    }
    if (cEmail != NULL) {
        (*env)->ReleaseStringUTFChars(env, email, cEmail);
    }
    if (cFullName != NULL) {
        (*env)->ReleaseStringUTFChars(env, fullName, cFullName);
    }
}
