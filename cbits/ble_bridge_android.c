/*
 * Android implementation of the BLE scanning bridge callbacks.
 *
 * Uses JNI to call Activity.checkBleAdapter(), Activity.startBleScan(),
 * and Activity.stopBleScan(). Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread, the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <android/log.h>
#include "BleBridge.h"
#include "JniBridge.h"

#define LOG_TAG "BleBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Haskell FFI export (dispatches scan result back to Haskell callback) */
extern void haskellOnBleScanResult(void *ctx, const char *name, const char *address, int32_t rssi);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env          = NULL;
static jobject  g_activity      = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx   = NULL;   /* stored for async JNI callback */

/* Cached JNI method IDs */
static jmethodID g_method_checkBleAdapter;
static jmethodID g_method_startBleScan;
static jmethodID g_method_stopBleScan;

/* ---- BLE bridge implementations ---- */

static int32_t android_ble_check_adapter(void)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("ble_check_adapter: bridge not initialized");
        return BLE_ADAPTER_UNSUPPORTED;
    }

    jint result = (*env)->CallIntMethod(env, g_activity, g_method_checkBleAdapter);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("ble_check_adapter: Java exception thrown");
        (*env)->ExceptionClear(env);
        return BLE_ADAPTER_UNSUPPORTED;
    }
    LOGI("ble_check_adapter() -> %d", result);
    return (int32_t)result;
}

static void android_ble_start_scan(void *ctx)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("ble_start_scan: bridge not initialized");
        return;
    }

    g_haskell_ctx = ctx;
    LOGI("ble_start_scan()");
    (*env)->CallVoidMethod(env, g_activity, g_method_startBleScan);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("ble_start_scan: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

static void android_ble_stop_scan(void)
{
    JNIEnv *env = g_env;
    if (!env || !g_activity) {
        LOGE("ble_stop_scan: bridge not initialized");
        return;
    }

    LOGI("ble_stop_scan()");
    (*env)->CallVoidMethod(env, g_activity, g_method_stopBleScan);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("ble_stop_scan: Java exception thrown");
        (*env)->ExceptionClear(env);
    }
}

/* ---- Public API ---- */

/*
 * Set up the Android BLE bridge. Called from jni_bridge.c
 * during renderUI (after the Activity is available).
 * Resolves JNI method IDs and registers callbacks with the
 * platform-agnostic dispatcher.
 */
void setup_android_ble_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_haskell_ctx = haskellCtx;

    if (!g_activity) {
        g_activity = (*env)->NewGlobalRef(env, activity);
    }

    jclass actClass = (*env)->GetObjectClass(env, activity);

    g_method_checkBleAdapter = (*env)->GetMethodID(env, actClass,
        "checkBleAdapter", "()I");
    g_method_startBleScan = (*env)->GetMethodID(env, actClass,
        "startBleScan", "()V");
    g_method_stopBleScan = (*env)->GetMethodID(env, actClass,
        "stopBleScan", "()V");

    /* Clean up local reference */
    (*env)->DeleteLocalRef(env, actClass);

    if (!g_method_checkBleAdapter || !g_method_startBleScan || !g_method_stopBleScan) {
        LOGE("Failed to resolve BLE JNI method IDs — BLE bridge disabled");
        (*env)->ExceptionClear(env);
        return;
    }

    /* Clear any unexpected pending exception before continuing */
    if ((*env)->ExceptionCheck(env)) {
        LOGE("Unexpected JNI exception after BLE method resolution");
        (*env)->ExceptionClear(env);
    }

    ble_register_impl(android_ble_check_adapter, android_ble_start_scan, android_ble_stop_scan);

    LOGI("Android BLE bridge initialized");
}

/* ---- JNI callback from Java BLE scan result ---- */

JNIEXPORT void JNICALL
JNI_METHOD(onBleScanResult)(JNIEnv *env, jobject thiz, jstring jname, jstring jaddr, jint rssi)
{
    g_env = env;

    const char *cname = NULL;
    const char *caddr = NULL;

    if (jname) {
        cname = (*env)->GetStringUTFChars(env, jname, NULL);
    }
    if (jaddr) {
        caddr = (*env)->GetStringUTFChars(env, jaddr, NULL);
    }

    LOGI("onBleScanResult(name=%s, addr=%s, rssi=%d)", cname ? cname : "(null)", caddr ? caddr : "(null)", rssi);
    haskellOnBleScanResult(g_haskell_ctx, cname, caddr, (int32_t)rssi);

    if (cname) {
        (*env)->ReleaseStringUTFChars(env, jname, cname);
    }
    if (caddr) {
        (*env)->ReleaseStringUTFChars(env, jaddr, caddr);
    }
}
