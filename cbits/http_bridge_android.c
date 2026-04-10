/*
 * Android implementation of the HTTP bridge callback.
 *
 * Uses JNI to call Activity.httpRequest(requestId, method, url, headers, body)
 * which spawns a background Thread using HttpURLConnection, then calls
 * onHttpResult on the UI thread via runOnUiThread.
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread — the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "HttpBridge.h"
#include "JniBridge.h"

#define LOG_TAG "HttpBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnHttpResult(void *ctx, int32_t requestId,
                                 int32_t resultCode, int32_t httpStatus,
                                 const char *headers,
                                 const char *body, int32_t bodyLen);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env         = NULL;
static jobject  g_activity     = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx  = NULL;

/* Cached JNI method ID */
static jmethodID g_method_httpRequest;

/* ---- HTTP bridge implementation ---- */

static void android_http_request(void *ctx, int32_t requestId, int32_t method,
                                  const char *url, const char *headers,
                                  const char *body, int32_t bodyLen)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("http_request: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    jstring jUrl = (*env)->NewStringUTF(env, url);
    jstring jHeaders = headers ? (*env)->NewStringUTF(env, headers) : NULL;
    jbyteArray jBody = NULL;
    if (body && bodyLen > 0) {
        jBody = (*env)->NewByteArray(env, bodyLen);
        (*env)->SetByteArrayRegion(env, jBody, 0, bodyLen, (const jbyte *)body);
    }

    LOGI("http_request(method=%d, url=\"%s\", id=%d)", method, url, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_httpRequest,
                           (jint)requestId, (jint)method,
                           jUrl, jHeaders, jBody);

    (*env)->DeleteLocalRef(env, jUrl);
    if (jHeaders) (*env)->DeleteLocalRef(env, jHeaders);
    if (jBody) (*env)->DeleteLocalRef(env, jBody);
}

/* ---- Public API ---- */

/*
 * Set up the Android HTTP bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callback with the
 * platform-agnostic dispatcher.
 */
void setup_android_http_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_httpRequest = (*env)->GetMethodID(env, actClass,
        "httpRequest", "(IILjava/lang/String;Ljava/lang/String;[B)V");

    if (!g_method_httpRequest) {
        LOGE("Failed to resolve httpRequest JNI method ID — bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    http_register_impl(android_http_request);

    LOGI("Android HTTP bridge initialized");
}

/* ---- JNI callback from Java ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onHttpResult)(JNIEnv *env, jobject thiz,
                          jint requestId, jint resultCode, jint httpStatus,
                          jstring headers, jbyteArray body)
{
    g_env = env;
    const char *cHeaders = NULL;
    const char *cBody = NULL;
    int32_t bodyLen = 0;

    if (headers != NULL) {
        cHeaders = (*env)->GetStringUTFChars(env, headers, NULL);
    }

    jbyte *bodyBytes = NULL;
    if (body != NULL) {
        bodyLen = (*env)->GetArrayLength(env, body);
        bodyBytes = (*env)->GetByteArrayElements(env, body, NULL);
        cBody = (const char *)bodyBytes;
    }

    LOGI("onHttpResult(requestId=%d, resultCode=%d, httpStatus=%d, bodyLen=%d)",
         requestId, resultCode, httpStatus, bodyLen);

    haskellOnHttpResult(g_haskell_ctx, (int32_t)requestId,
                         (int32_t)resultCode, (int32_t)httpStatus,
                         cHeaders, cBody, bodyLen);

    if (cHeaders != NULL) {
        (*env)->ReleaseStringUTFChars(env, headers, cHeaders);
    }
    if (bodyBytes != NULL) {
        (*env)->ReleaseByteArrayElements(env, body, bodyBytes, JNI_ABORT);
    }
}
