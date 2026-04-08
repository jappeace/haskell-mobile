/*
 * Android implementation of the secure storage bridge callbacks.
 *
 * Uses JNI to call Activity.secureStorageWrite/Read/Delete() which
 * delegate to SharedPreferences with MODE_PRIVATE.
 * Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread — the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "SecureStorageBridge.h"
#include "JniBridge.h"

#define LOG_TAG "SecureStorageBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnSecureStorageResult(void *ctx, int32_t requestId,
                                          int32_t statusCode, const char *value);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env         = NULL;
static jobject  g_activity     = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx  = NULL;   /* stored per-request for async JNI callback */

/* Cached JNI method IDs */
static jmethodID g_method_secureStorageWrite;
static jmethodID g_method_secureStorageRead;
static jmethodID g_method_secureStorageDelete;

/* ---- Secure storage bridge implementations ---- */

static void android_secure_storage_write(void *ctx, int32_t requestId,
                                          const char *key, const char *value)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("secure_storage_write: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    jstring jkey = (*env)->NewStringUTF(env, key);
    jstring jvalue = (*env)->NewStringUTF(env, value);
    LOGI("secure_storage_write(key=\"%s\", id=%d)", key, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_secureStorageWrite,
                           (jint)requestId, jkey, jvalue);
    (*env)->DeleteLocalRef(env, jkey);
    (*env)->DeleteLocalRef(env, jvalue);
}

static void android_secure_storage_read(void *ctx, int32_t requestId,
                                         const char *key)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("secure_storage_read: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    jstring jkey = (*env)->NewStringUTF(env, key);
    LOGI("secure_storage_read(key=\"%s\", id=%d)", key, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_secureStorageRead,
                           (jint)requestId, jkey);
    (*env)->DeleteLocalRef(env, jkey);
}

static void android_secure_storage_delete(void *ctx, int32_t requestId,
                                           const char *key)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("secure_storage_delete: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;

    jstring jkey = (*env)->NewStringUTF(env, key);
    LOGI("secure_storage_delete(key=\"%s\", id=%d)", key, requestId);
    (*env)->CallVoidMethod(env, g_activity, g_method_secureStorageDelete,
                           (jint)requestId, jkey);
    (*env)->DeleteLocalRef(env, jkey);
}

/* ---- Public API ---- */

/*
 * Set up the Android secure storage bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callbacks with the
 * platform-agnostic dispatcher.
 */
void setup_android_secure_storage_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_secureStorageWrite = (*env)->GetMethodID(env, actClass,
        "secureStorageWrite", "(ILjava/lang/String;Ljava/lang/String;)V");
    g_method_secureStorageRead = (*env)->GetMethodID(env, actClass,
        "secureStorageRead", "(ILjava/lang/String;)V");
    g_method_secureStorageDelete = (*env)->GetMethodID(env, actClass,
        "secureStorageDelete", "(ILjava/lang/String;)V");

    if (!g_method_secureStorageWrite || !g_method_secureStorageRead ||
        !g_method_secureStorageDelete) {
        LOGE("Failed to resolve secure storage JNI method IDs — bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    secure_storage_register_impl(android_secure_storage_write,
                                  android_secure_storage_read,
                                  android_secure_storage_delete);

    LOGI("Android secure storage bridge initialized");
}

/* ---- JNI callback from Java ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onSecureStorageResult)(JNIEnv *env, jobject thiz,
                                   jint requestId, jint statusCode, jstring value)
{
    g_env = env;
    const char *cvalue = NULL;
    if (value != NULL) {
        cvalue = (*env)->GetStringUTFChars(env, value, NULL);
    }
    LOGI("onSecureStorageResult(requestId=%d, statusCode=%d, value=%s)",
         requestId, statusCode, cvalue ? cvalue : "NULL");
    haskellOnSecureStorageResult(g_haskell_ctx, (int32_t)requestId,
                                 (int32_t)statusCode, cvalue);
    if (cvalue != NULL) {
        (*env)->ReleaseStringUTFChars(env, value, cvalue);
    }
}
