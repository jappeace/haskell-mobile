/*
 * JNI bridge between Android Java and Haskell FFI exports.
 *
 * This file is compiled by NDK clang (not cabal), and linked into
 * libhatter.so alongside the Haskell static library.
 *
 * The Java package name is controlled by -DJNI_PACKAGE at compile time;
 * see include/JniBridge.h for defaults.
 */

#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>
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
#include "NetworkStatusBridge.h"
#include "AnimationBridge.h"
#include "RedrawBridge.h"
#include "PlatformSignInBridge.h"

/* Deduplicate registerForeignExports to prevent OOM on armv7a.
 *
 * When --whole-archive pulls in GHC boot libraries, duplicate .init_array
 * entries can cause registerForeignExports to be called twice with the
 * same ForeignExportsList struct.  The second call creates a self-referencing
 * linked list (struct->next = &struct).  processForeignExports then loops
 * infinitely, calling getStablePtr billions of times and doubling
 * enlargeStablePtrTable until the 32-bit address space is exhausted.
 *
 * Linked via -Wl,--wrap=registerForeignExports (unconditional in lib.nix).
 *
 * See: https://github.com/jappeace/hatter/issues/163
 */
struct ForeignExportsList {
    struct ForeignExportsList *next;
    int n_entries;
    void *exports[];
};

extern void __real_registerForeignExports(struct ForeignExportsList *exports);

static struct ForeignExportsList *g_seen_fexports[64];
static int g_seen_fexports_count = 0;

void __wrap_registerForeignExports(struct ForeignExportsList *exports) {
    for (int i = 0; i < g_seen_fexports_count; i++) {
        if (g_seen_fexports[i] == exports) {
            __android_log_print(ANDROID_LOG_WARN, "HatterInit",
                "registerForeignExports: duplicate struct %p — skipping",
                (void*)exports);
            return;
        }
    }
    if (g_seen_fexports_count < 64) {
        g_seen_fexports[g_seen_fexports_count++] = exports;
    }
    __real_registerForeignExports(exports);
}

/* Runs the user's Haskell main via RTS API (cbits/run_main.c).
 * Returns the opaque AppContext pointer. */
extern void *haskellRunMain(void);

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (Hatter.Locale) */
extern void haskellLogLocale(void);

/* App files directory (cbits/files_dir.c) */
extern void setAppFilesDir(const char *path);

/* Device info (cbits/device_info.c) */
extern void setDeviceModel(const char *value);
extern void setDeviceOsVersion(const char *value);
extern void setDeviceScreenDensity(const char *value);
extern void setDeviceScreenWidth(const char *value);
extern void setDeviceScreenHeight(const char *value);

/* Log device info from Haskell (Hatter.DeviceInfo) */
extern void haskellLogDeviceInfo(void);

/* Haskell foreign exports */
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
extern void haskellOnNetworkStatusChange(void *ctx, int connected, int transport);
extern void haskellOnAnimationFrame(void *ctx, double timestampMs);
extern void haskellOnPlatformSignInResult(void *ctx, int32_t requestId,
                                           int32_t statusCode,
                                           const char *identityToken,
                                           const char *userId,
                                           const char *email,
                                           const char *fullName,
                                           int32_t provider);

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

/* Android network status bridge (from network_status_android.c) */
extern void setup_android_network_status_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android animation bridge (from animation_bridge_android.c) */
extern void setup_android_animation_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android redraw bridge (from redraw_bridge_android.c) */
extern void setup_android_redraw_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Android platform sign-in bridge (from platform_sign_in_android.c) */
extern void setup_android_platform_sign_in_bridge(JNIEnv *env, jobject activity, void *haskellCtx);

/* Lifecycle event codes (must match Hatter.h) */
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

    /* Pre-haskellRunMain platform init: set globals that Haskell code may
       read immediately (e.g. in startMobileApp callbacks). */
    {
        JNIEnv *env;
        (*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6);

        /* Locale: Locale.getDefault().toLanguageTag() (static, no context needed) */
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

        /* Files dir: ActivityThread.currentApplication().getFilesDir().
           The Application exists before any Activity, so this is available
           during JNI_OnLoad (called from System.loadLibrary). */
        jclass atClass = (*env)->FindClass(env, "android/app/ActivityThread");
        jmethodID currentApp = (*env)->GetStaticMethodID(env, atClass,
            "currentApplication", "()Landroid/app/Application;");
        jobject app = (*env)->CallStaticObjectMethod(env, atClass, currentApp);
        if (app) {
            jclass ctxClass = (*env)->FindClass(env, "android/content/Context");
            jmethodID getFilesDir = (*env)->GetMethodID(env, ctxClass,
                "getFilesDir", "()Ljava/io/File;");
            jobject filesDir = (*env)->CallObjectMethod(env, app, getFilesDir);
            if (filesDir) {
                jclass fileClass = (*env)->FindClass(env, "java/io/File");
                jmethodID getAbsPath = (*env)->GetMethodID(env, fileClass,
                    "getAbsolutePath", "()Ljava/lang/String;");
                jstring jpath = (*env)->CallObjectMethod(env, filesDir, getAbsPath);
                const char *cpath = (*env)->GetStringUTFChars(env, jpath, NULL);
                setAppFilesDir(strdup(cpath));
                (*env)->ReleaseStringUTFChars(env, jpath, cpath);
            }
        }

        /* Device info: Build.MODEL */
        {
            jclass buildClass = (*env)->FindClass(env, "android/os/Build");
            jfieldID modelField = (*env)->GetStaticFieldID(env, buildClass,
                "MODEL", "Ljava/lang/String;");
            jstring jmodel = (*env)->GetStaticObjectField(env, buildClass, modelField);
            const char *cmodel = (*env)->GetStringUTFChars(env, jmodel, NULL);
            setDeviceModel(strdup(cmodel));
            (*env)->ReleaseStringUTFChars(env, jmodel, cmodel);
        }

        /* Device info: Build.VERSION.RELEASE */
        {
            jclass versionClass = (*env)->FindClass(env, "android/os/Build$VERSION");
            jfieldID releaseField = (*env)->GetStaticFieldID(env, versionClass,
                "RELEASE", "Ljava/lang/String;");
            jstring jrelease = (*env)->GetStaticObjectField(env, versionClass, releaseField);
            const char *crelease = (*env)->GetStringUTFChars(env, jrelease, NULL);
            setDeviceOsVersion(strdup(crelease));
            (*env)->ReleaseStringUTFChars(env, jrelease, crelease);
        }

        /* Device info: DisplayMetrics (density, width, height) */
        {
            jclass resourcesClass = (*env)->FindClass(env, "android/content/res/Resources");
            jmethodID getSystem = (*env)->GetStaticMethodID(env, resourcesClass,
                "getSystem", "()Landroid/content/res/Resources;");
            jobject resources = (*env)->CallStaticObjectMethod(env, resourcesClass, getSystem);
            jmethodID getDisplayMetrics = (*env)->GetMethodID(env, resourcesClass,
                "getDisplayMetrics", "()Landroid/util/DisplayMetrics;");
            jobject metrics = (*env)->CallObjectMethod(env, resources, getDisplayMetrics);

            jclass dmClass = (*env)->FindClass(env, "android/util/DisplayMetrics");

            jfieldID densityField = (*env)->GetFieldID(env, dmClass, "density", "F");
            float density = (*env)->GetFloatField(env, metrics, densityField);
            char densityBuf[32];
            snprintf(densityBuf, sizeof(densityBuf), "%.2f", density);
            setDeviceScreenDensity(strdup(densityBuf));

            jfieldID widthField = (*env)->GetFieldID(env, dmClass, "widthPixels", "I");
            int width = (*env)->GetIntField(env, metrics, widthField);
            char widthBuf[32];
            snprintf(widthBuf, sizeof(widthBuf), "%d", width);
            setDeviceScreenWidth(strdup(widthBuf));

            jfieldID heightField = (*env)->GetFieldID(env, dmClass, "heightPixels", "I");
            int height = (*env)->GetIntField(env, metrics, heightField);
            char heightBuf[32];
            snprintf(heightBuf, sizeof(heightBuf), "%d", height);
            setDeviceScreenHeight(strdup(heightBuf));
        }
    }

    g_haskell_ctx = haskellRunMain();
    haskellLogLocale();
    haskellLogDeviceInfo();

    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
JNI_OnUnload(JavaVM *vm, void *reserved)
{
    hs_exit();
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
    setup_android_network_status_bridge(env, thiz, g_haskell_ctx);
    setup_android_animation_bridge(env, thiz, g_haskell_ctx);
    setup_android_redraw_bridge(env, thiz, g_haskell_ctx);
    setup_android_platform_sign_in_bridge(env, thiz, g_haskell_ctx);
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
