/*
 * JNI bridge between Android Java and Haskell FFI exports.
 *
 * This file is compiled by NDK clang (not cabal), and linked into
 * libhaskellmobile.so alongside the Haskell static library.
 *
 * The Java package name is controlled by -DJNI_PACKAGE at compile time;
 * see include/JniBridge.h for defaults.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>
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

/* Runs the user's Haskell main via RTS API (cbits/run_main.c).
 * Returns the opaque AppContext pointer. */
extern void *haskellRunMain(void);

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (HaskellMobile.Locale) */
extern void haskellLogLocale(void);

/* Haskell foreign exports */
extern char* haskellGreet(const char* name);
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

/* Lifecycle event codes (must match HaskellMobile.h) */
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
    hs_init(NULL, NULL);
    g_haskell_ctx = haskellRunMain();

    /* Cache the system locale from Android's Locale.getDefault().toLanguageTag() */
    {
        JNIEnv *env;
        (*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6);

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

        haskellLogLocale();
    }

    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
JNI_OnUnload(JavaVM *vm, void *reserved)
{
    hs_exit();
}

JNIEXPORT jstring JNICALL
JNI_METHOD(greet)(JNIEnv *env, jobject thiz, jstring jname)
{
    const char *cname = (*env)->GetStringUTFChars(env, jname, NULL);
    if (cname == NULL) {
        return NULL; /* OutOfMemoryError already thrown */
    }

    char *cresult = haskellGreet(cname);
    (*env)->ReleaseStringUTFChars(env, jname, cname);

    jstring jresult = (*env)->NewStringUTF(env, cresult);
    free(cresult);

    return jresult;
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
