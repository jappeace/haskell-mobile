/*
 * Android implementation of the UI bridge callbacks.
 *
 * Uses JNI to create Android views (TextView, Button, LinearLayout)
 * and manage the view hierarchy. Compiled by NDK clang, not cabal.
 *
 * All functions run on the main/UI thread — the same thread that
 * calls haskellRenderUI from Java.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>
#include "UIBridge.h"

#define LOG_TAG "UIBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* --- Node pool configuration ---
 *
 * Two compile-time flags control the pool strategy:
 *   -DMAX_NODES=N         Override the static pool size (default 256).
 *   -DDYNAMIC_NODE_POOL   Use malloc/realloc; MAX_NODES is ignored.
 *
 * Re-renders clear all nodes, so the pool only bounds a single frame. */
#ifdef DYNAMIC_NODE_POOL
  static jobject *g_nodes         = NULL;
  static int32_t  g_pool_capacity = 0;
  #define INITIAL_POOL_SIZE 256
#else
  #ifndef MAX_NODES
  #define MAX_NODES 256
  #endif
  static jobject  g_nodes[MAX_NODES];
#endif
static int32_t g_next_node_id = 1;

/* Haskell FFI exports (declared here since this file is compiled by NDK) */
extern void haskellOnUIEvent(void *ctx, int callbackId);
extern void haskellOnUITextChange(void *ctx, int callbackId, const char *text);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env      = NULL;
static jobject  g_activity  = NULL;   /* global ref to Activity */

/* ---- Per-button callback IDs stored as view tags ---- */

/* Cached JNI class/method IDs (resolved once in setup) */
static jclass   g_class_TextView;
static jclass   g_class_Button;
static jclass   g_class_EditText;
static jclass   g_class_LinearLayout;
static jclass   g_class_ScrollView;
static jclass   g_class_ImageView;
static jclass   g_class_WebView;
static jclass   g_class_FrameLayout;
static jclass   g_class_BitmapFactory;
static jclass   g_class_ViewGroup;
static jclass   g_class_ViewGroup_LayoutParams;
static jclass   g_class_Integer;

static jmethodID g_ctor_TextView;
static jmethodID g_ctor_Button;
static jmethodID g_ctor_EditText;
static jmethodID g_ctor_LinearLayout;
static jmethodID g_ctor_ScrollView;
static jmethodID g_ctor_ImageView;
static jmethodID g_ctor_WebView;
static jmethodID g_ctor_FrameLayout;
static jmethodID g_ctor_ViewGroup_LayoutParams;
static jmethodID g_ctor_Integer;

static jmethodID g_method_setText;
static jmethodID g_method_setHint;
static jmethodID g_method_setOrientation;
static jmethodID g_method_addView;
static jmethodID g_method_removeView;
static jmethodID g_method_removeAllViews;
static jmethodID g_method_setContentView;
static jmethodID g_method_setTag;
static jmethodID g_method_getTag;
static jmethodID g_method_intValue;
static jmethodID g_method_setOnClickListener;
static jmethodID g_method_registerTextWatcher;
static jmethodID g_method_setInputType;
static jmethodID g_method_setTextSize;
static jmethodID g_method_setPadding;
static jmethodID g_method_setGravity_TextView;
static jmethodID g_method_setGravity_LinearLayout;
static jmethodID g_method_setLayoutParams;
static jmethodID g_method_setTextColor;
static jmethodID g_method_setBackgroundColor;
static jmethodID g_method_setImageBitmap;
static jmethodID g_method_setScaleType;
static jmethodID g_method_decodeByteArray;
static jmethodID g_method_decodeFile;
static jmethodID g_method_loadUrl;
static jmethodID g_method_getSettings;
static jmethodID g_method_setJavaScriptEnabled;
static jmethodID g_method_registerWebViewClient;

/* LinearLayout orientation constants */
static jint ORIENTATION_VERTICAL   = 1;
static jint ORIENTATION_HORIZONTAL = 0;

/* ---- Forward declarations ---- */
static int32_t android_create_node(int32_t nodeType);
static void    android_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
static void    android_set_num_prop(int32_t nodeId, int32_t propId, double value);
static void    android_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length);
static void    android_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
static void    android_add_child(int32_t parentId, int32_t childId);
static void    android_remove_child(int32_t parentId, int32_t childId);
static void    android_destroy_node(int32_t nodeId);
static void    android_set_root(int32_t nodeId);
static void    android_clear(void);

static UIBridgeCallbacks g_android_callbacks = {
    .createNode   = android_create_node,
    .setStrProp   = android_set_str_prop,
    .setNumProp   = android_set_num_prop,
    .setImageData = android_set_image_data,
    .setHandler   = android_set_handler,
    .addChild     = android_add_child,
    .removeChild  = android_remove_child,
    .destroyNode  = android_destroy_node,
    .setRoot      = android_set_root,
    .clear        = android_clear,
};

/* ---- JNI class/method resolution ---- */
static int resolve_jni_ids(JNIEnv *env, jobject activity)
{
    /* Resolve classes */
    jclass cls;

    cls = (*env)->FindClass(env, "android/widget/TextView");
    if (!cls) return -1;
    g_class_TextView = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/Button");
    if (!cls) return -1;
    g_class_Button = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/EditText");
    if (!cls) return -1;
    g_class_EditText = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/LinearLayout");
    if (!cls) return -1;
    g_class_LinearLayout = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/ScrollView");
    if (!cls) return -1;
    g_class_ScrollView = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/ImageView");
    if (!cls) return -1;
    g_class_ImageView = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/webkit/WebView");
    if (!cls) return -1;
    g_class_WebView = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/widget/FrameLayout");
    if (!cls) return -1;
    g_class_FrameLayout = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/graphics/BitmapFactory");
    if (!cls) return -1;
    g_class_BitmapFactory = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/view/ViewGroup");
    if (!cls) return -1;
    g_class_ViewGroup = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "android/view/ViewGroup$LayoutParams");
    if (!cls) return -1;
    g_class_ViewGroup_LayoutParams = (*env)->NewGlobalRef(env, cls);

    cls = (*env)->FindClass(env, "java/lang/Integer");
    if (!cls) return -1;
    g_class_Integer = (*env)->NewGlobalRef(env, cls);

    /* Resolve constructors */
    g_ctor_TextView = (*env)->GetMethodID(env, g_class_TextView,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_Button = (*env)->GetMethodID(env, g_class_Button,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_EditText = (*env)->GetMethodID(env, g_class_EditText,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_LinearLayout = (*env)->GetMethodID(env, g_class_LinearLayout,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_ScrollView = (*env)->GetMethodID(env, g_class_ScrollView,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_ImageView = (*env)->GetMethodID(env, g_class_ImageView,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_WebView = (*env)->GetMethodID(env, g_class_WebView,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_FrameLayout = (*env)->GetMethodID(env, g_class_FrameLayout,
        "<init>", "(Landroid/content/Context;)V");
    g_ctor_ViewGroup_LayoutParams = (*env)->GetMethodID(env,
        g_class_ViewGroup_LayoutParams, "<init>", "(II)V");
    g_ctor_Integer = (*env)->GetMethodID(env, g_class_Integer,
        "<init>", "(I)V");

    /* Resolve methods */
    g_method_setText = (*env)->GetMethodID(env, g_class_TextView,
        "setText", "(Ljava/lang/CharSequence;)V");
    g_method_setHint = (*env)->GetMethodID(env, g_class_TextView,
        "setHint", "(Ljava/lang/CharSequence;)V");
    g_method_setOrientation = (*env)->GetMethodID(env, g_class_LinearLayout,
        "setOrientation", "(I)V");
    g_method_addView = (*env)->GetMethodID(env, g_class_ViewGroup,
        "addView", "(Landroid/view/View;)V");
    g_method_removeView = (*env)->GetMethodID(env, g_class_ViewGroup,
        "removeView", "(Landroid/view/View;)V");
    g_method_removeAllViews = (*env)->GetMethodID(env, g_class_ViewGroup,
        "removeAllViews", "()V");

    /* Activity.setContentView(View) */
    jclass activityClass = (*env)->GetObjectClass(env, activity);
    g_method_setContentView = (*env)->GetMethodID(env, activityClass,
        "setContentView", "(Landroid/view/View;)V");

    /* View.setTag / getTag for storing callback IDs */
    jclass viewClass = (*env)->FindClass(env, "android/view/View");
    g_method_setTag = (*env)->GetMethodID(env, viewClass,
        "setTag", "(Ljava/lang/Object;)V");
    g_method_getTag = (*env)->GetMethodID(env, viewClass,
        "getTag", "()Ljava/lang/Object;");

    g_method_intValue = (*env)->GetMethodID(env, g_class_Integer,
        "intValue", "()I");

    /* View.setOnClickListener(OnClickListener) — Activity implements it */
    g_method_setOnClickListener = (*env)->GetMethodID(env, viewClass,
        "setOnClickListener", "(Landroid/view/View$OnClickListener;)V");

    /* Activity.registerTextWatcher(EditText) — our custom Java method */
    jclass actClass = (*env)->GetObjectClass(env, activity);
    g_method_registerTextWatcher = (*env)->GetMethodID(env, actClass,
        "registerTextWatcher", "(Landroid/widget/EditText;)V");
    if (!g_method_registerTextWatcher) {
        LOGE("registerTextWatcher not found — text input events disabled");
        (*env)->ExceptionClear(env);
    }

    /* EditText.setInputType(int) */
    g_method_setInputType = (*env)->GetMethodID(env, g_class_EditText,
        "setInputType", "(I)V");

    /* TextView.setTextSize(float) — sets size in scaled pixels */
    g_method_setTextSize = (*env)->GetMethodID(env, g_class_TextView,
        "setTextSize", "(F)V");

    /* View.setPadding(int,int,int,int) — sets padding in pixels */
    g_method_setPadding = (*env)->GetMethodID(env, viewClass,
        "setPadding", "(IIII)V");

    /* TextView.setGravity(int) — sets text alignment */
    g_method_setGravity_TextView = (*env)->GetMethodID(env, g_class_TextView,
        "setGravity", "(I)V");

    /* LinearLayout.setGravity(int) — centers children */
    g_method_setGravity_LinearLayout = (*env)->GetMethodID(env, g_class_LinearLayout,
        "setGravity", "(I)V");

    /* View.setLayoutParams(ViewGroup.LayoutParams) — needed to set MATCH_PARENT width */
    g_method_setLayoutParams = (*env)->GetMethodID(env, viewClass,
        "setLayoutParams", "(Landroid/view/ViewGroup$LayoutParams;)V");

    /* TextView.setTextColor(int) — sets ARGB text color */
    g_method_setTextColor = (*env)->GetMethodID(env, g_class_TextView,
        "setTextColor", "(I)V");

    /* View.setBackgroundColor(int) — sets ARGB background color */
    g_method_setBackgroundColor = (*env)->GetMethodID(env, viewClass,
        "setBackgroundColor", "(I)V");

    /* ImageView.setImageBitmap(Bitmap) */
    g_method_setImageBitmap = (*env)->GetMethodID(env, g_class_ImageView,
        "setImageBitmap", "(Landroid/graphics/Bitmap;)V");

    /* ImageView.setScaleType(ImageView.ScaleType) */
    g_method_setScaleType = (*env)->GetMethodID(env, g_class_ImageView,
        "setScaleType", "(Landroid/widget/ImageView$ScaleType;)V");

    /* BitmapFactory.decodeByteArray(byte[], int, int) -> Bitmap */
    g_method_decodeByteArray = (*env)->GetStaticMethodID(env, g_class_BitmapFactory,
        "decodeByteArray", "([BII)Landroid/graphics/Bitmap;");

    /* BitmapFactory.decodeFile(String) -> Bitmap */
    g_method_decodeFile = (*env)->GetStaticMethodID(env, g_class_BitmapFactory,
        "decodeFile", "(Ljava/lang/String;)Landroid/graphics/Bitmap;");

    /* WebView.loadUrl(String) */
    g_method_loadUrl = (*env)->GetMethodID(env, g_class_WebView,
        "loadUrl", "(Ljava/lang/String;)V");

    /* WebView.getSettings() -> WebSettings */
    g_method_getSettings = (*env)->GetMethodID(env, g_class_WebView,
        "getSettings", "()Landroid/webkit/WebSettings;");

    /* WebSettings.setJavaScriptEnabled(boolean) */
    {
        jclass webSettingsClass = (*env)->FindClass(env, "android/webkit/WebSettings");
        if (webSettingsClass) {
            g_method_setJavaScriptEnabled = (*env)->GetMethodID(env, webSettingsClass,
                "setJavaScriptEnabled", "(Z)V");
            (*env)->DeleteLocalRef(env, webSettingsClass);
        }
    }

    /* Activity.registerWebViewClient(WebView) — our custom Java method */
    g_method_registerWebViewClient = (*env)->GetMethodID(env, actClass,
        "registerWebViewClient", "(Landroid/webkit/WebView;)V");
    if (!g_method_registerWebViewClient) {
        LOGE("registerWebViewClient not found — webview page-load events disabled");
        (*env)->ExceptionClear(env);
    }

    /* Clear any pending exception from optional method lookups above */
    if ((*env)->ExceptionCheck(env)) {
        LOGE("JNI exception during resolve_jni_ids — clearing");
        (*env)->ExceptionClear(env);
    }

    return 0;
}

/* ---- Node pool helpers ---- */

#ifdef DYNAMIC_NODE_POOL
/* Grow the pool so that nodeId < g_pool_capacity. */
static int ensure_pool_capacity(int32_t needed)
{
    if (needed < g_pool_capacity) return 0;
    int32_t new_cap = g_pool_capacity ? g_pool_capacity : INITIAL_POOL_SIZE;
    while (new_cap <= needed) new_cap *= 2;
    jobject *new_pool = realloc(g_nodes, (size_t)new_cap * sizeof(jobject));
    if (!new_pool) {
        LOGE("Node pool realloc failed (requested %d slots)", new_cap);
        return -1;
    }
    memset(new_pool + g_pool_capacity, 0,
           (size_t)(new_cap - g_pool_capacity) * sizeof(jobject));
    g_nodes = new_pool;
    g_pool_capacity = new_cap;
    return 0;
}
#endif

static jobject get_node(int32_t nodeId)
{
#ifdef DYNAMIC_NODE_POOL
    if (nodeId < 1 || nodeId >= g_pool_capacity) return NULL;
#else
    if (nodeId < 1 || nodeId >= MAX_NODES) return NULL;
#endif
    return g_nodes[nodeId];
}

/* ---- Hex color parser ---- */

/*
 * Parse a hex color string (#RGB, #RRGGBB, or #AARRGGBB) into a jint ARGB value.
 * Returns 0 (transparent black) on invalid input.
 */
static jint parse_hex_color(const char *hex)
{
    if (!hex || hex[0] != '#') return 0;
    const char *digits = hex + 1;
    size_t len = strlen(digits);
    unsigned long raw = strtoul(digits, NULL, 16);

    switch (len) {
    case 3: {
        /* #RGB -> #FFRRGGBB (expand each nibble) */
        unsigned int r = (raw >> 8) & 0xF;
        unsigned int g = (raw >> 4) & 0xF;
        unsigned int b = raw & 0xF;
        return (jint)(0xFF000000u | (r * 0x11u) << 16 | (g * 0x11u) << 8 | (b * 0x11u));
    }
    case 6:
        /* #RRGGBB -> #FFRRGGBB */
        return (jint)(0xFF000000u | (raw & 0xFFFFFFu));
    case 8:
        /* #AARRGGBB — already complete */
        return (jint)raw;
    default:
        return 0;
    }
}

/* ---- Callback implementation ---- */

static int32_t android_create_node(int32_t nodeType)
{
#ifdef DYNAMIC_NODE_POOL
    if (ensure_pool_capacity(g_next_node_id) != 0) {
        LOGE("Node pool exhausted (realloc failed at %d)", g_next_node_id);
        return 0;
    }
#else
    if (g_next_node_id >= MAX_NODES) {
        LOGE("Node pool exhausted (max %d)", MAX_NODES);
        return 0;
    }
#endif

    JNIEnv *env = g_env;
    jobject view = NULL;

    switch (nodeType) {
    case UI_NODE_TEXT:
        view = (*env)->NewObject(env, g_class_TextView, g_ctor_TextView, g_activity);
        break;
    case UI_NODE_BUTTON:
        view = (*env)->NewObject(env, g_class_Button, g_ctor_Button, g_activity);
        break;
    case UI_NODE_COLUMN: {
        view = (*env)->NewObject(env, g_class_LinearLayout, g_ctor_LinearLayout, g_activity);
        (*env)->CallVoidMethod(env, view, g_method_setOrientation, ORIENTATION_VERTICAL);
        break;
    }
    case UI_NODE_ROW: {
        view = (*env)->NewObject(env, g_class_LinearLayout, g_ctor_LinearLayout, g_activity);
        (*env)->CallVoidMethod(env, view, g_method_setOrientation, ORIENTATION_HORIZONTAL);
        break;
    }
    case UI_NODE_TEXT_INPUT:
        view = (*env)->NewObject(env, g_class_EditText, g_ctor_EditText, g_activity);
        break;
    case UI_NODE_SCROLL_VIEW:
        view = (*env)->NewObject(env, g_class_ScrollView, g_ctor_ScrollView, g_activity);
        break;
    case UI_NODE_IMAGE:
        view = (*env)->NewObject(env, g_class_ImageView, g_ctor_ImageView, g_activity);
        break;
    case UI_NODE_MAP_VIEW: {
        /* Placeholder: FrameLayout containing a TextView showing coordinates.
         * A real map (osmdroid or Google Maps) can replace this once the build
         * pipeline supports AAR dependencies. */
        jobject frame = (*env)->NewObject(env, g_class_FrameLayout, g_ctor_FrameLayout, g_activity);
        jobject label = (*env)->NewObject(env, g_class_TextView, g_ctor_TextView, g_activity);
        jstring text = (*env)->NewStringUTF(env, "Map placeholder (0.0, 0.0) z1.0");
        (*env)->CallVoidMethod(env, label, g_method_setText, text);
        (*env)->DeleteLocalRef(env, text);
        (*env)->CallVoidMethod(env, frame, g_method_addView, label);
        (*env)->DeleteLocalRef(env, label);
        view = frame;
        break;
    }
    case UI_NODE_WEBVIEW: {
        view = (*env)->NewObject(env, g_class_WebView, g_ctor_WebView, g_activity);
        if (view && g_method_getSettings && g_method_setJavaScriptEnabled) {
            jobject settings = (*env)->CallObjectMethod(env, view, g_method_getSettings);
            if (settings) {
                (*env)->CallVoidMethod(env, settings, g_method_setJavaScriptEnabled, JNI_TRUE);
                (*env)->DeleteLocalRef(env, settings);
            }
        }
        break;
    }
    default:
        LOGE("Unknown node type: %d", nodeType);
        return 0;
    }

    if (!view) {
        LOGE("Failed to create view for type %d", nodeType);
        return 0;
    }

    int32_t nodeId = g_next_node_id++;
    g_nodes[nodeId] = (*env)->NewGlobalRef(env, view);
    (*env)->DeleteLocalRef(env, view);

    LOGI("createNode(type=%d) -> %d", nodeType, nodeId);
    return nodeId;
}

static void android_set_str_prop(int32_t nodeId, int32_t propId, const char *value)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;

    switch (propId) {
    case UI_PROP_TEXT: {
        LOGI("setStrProp(node=%d, text=\"%s\")", nodeId, value);
        jstring jstr = (*env)->NewStringUTF(env, value);
        (*env)->CallVoidMethod(env, view, g_method_setText, jstr);
        (*env)->DeleteLocalRef(env, jstr);
        break;
    }
    case UI_PROP_HINT: {
        LOGI("setStrProp(node=%d, hint=\"%s\")", nodeId, value);
        jstring jstr = (*env)->NewStringUTF(env, value);
        (*env)->CallVoidMethod(env, view, g_method_setHint, jstr);
        (*env)->DeleteLocalRef(env, jstr);
        break;
    }
    case UI_PROP_COLOR: {
        LOGI("setStrProp(node=%d, color=\"%s\")", nodeId, value);
        if ((*env)->IsInstanceOf(env, view, g_class_TextView)) {
            jint argb = parse_hex_color(value);
            (*env)->CallVoidMethod(env, view, g_method_setTextColor, argb);
        }
        break;
    }
    case UI_PROP_BG_COLOR: {
        LOGI("setStrProp(node=%d, bgColor=\"%s\")", nodeId, value);
        jint argb = parse_hex_color(value);
        (*env)->CallVoidMethod(env, view, g_method_setBackgroundColor, argb);
        break;
    }
    case UI_PROP_IMAGE_RESOURCE: {
        LOGI("setStrProp(node=%d, imageResource=\"%s\")", nodeId, value);
        /* Resource lookup: getResources().getIdentifier(name, "drawable", packageName) */
        if ((*env)->IsInstanceOf(env, view, g_class_ImageView)) {
            jclass actClass = (*env)->GetObjectClass(env, g_activity);
            jmethodID getResources = (*env)->GetMethodID(env, actClass,
                "getResources", "()Landroid/content/res/Resources;");
            jmethodID getPackageName = (*env)->GetMethodID(env, actClass,
                "getPackageName", "()Ljava/lang/String;");
            jobject resources = (*env)->CallObjectMethod(env, g_activity, getResources);
            jstring packageName = (*env)->CallObjectMethod(env, g_activity, getPackageName);
            jclass resClass = (*env)->GetObjectClass(env, resources);
            jmethodID getIdentifier = (*env)->GetMethodID(env, resClass,
                "getIdentifier", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I");
            jmethodID getDrawable = (*env)->GetMethodID(env, resClass,
                "getDrawable", "(I)Landroid/graphics/drawable/Drawable;");
            jstring jname = (*env)->NewStringUTF(env, value);
            jstring jtype = (*env)->NewStringUTF(env, "drawable");
            jint resId = (*env)->CallIntMethod(env, resources, getIdentifier,
                jname, jtype, packageName);
            if (resId != 0) {
                jobject drawable = (*env)->CallObjectMethod(env, resources, getDrawable, resId);
                jmethodID setImageDrawable = (*env)->GetMethodID(env, g_class_ImageView,
                    "setImageDrawable", "(Landroid/graphics/drawable/Drawable;)V");
                (*env)->CallVoidMethod(env, view, setImageDrawable, drawable);
                (*env)->DeleteLocalRef(env, drawable);
            } else {
                LOGE("Resource not found: %s", value);
            }
            (*env)->DeleteLocalRef(env, jname);
            (*env)->DeleteLocalRef(env, jtype);
            (*env)->DeleteLocalRef(env, packageName);
            (*env)->DeleteLocalRef(env, resources);
        }
        break;
    }
    case UI_PROP_IMAGE_FILE: {
        LOGI("setStrProp(node=%d, imageFile=\"%s\")", nodeId, value);
        if ((*env)->IsInstanceOf(env, view, g_class_ImageView)) {
            jstring jpath = (*env)->NewStringUTF(env, value);
            jobject bitmap = (*env)->CallStaticObjectMethod(env,
                g_class_BitmapFactory, g_method_decodeFile, jpath);
            if (bitmap) {
                (*env)->CallVoidMethod(env, view, g_method_setImageBitmap, bitmap);
                (*env)->DeleteLocalRef(env, bitmap);
            } else {
                LOGE("Failed to decode file: %s", value);
            }
            (*env)->DeleteLocalRef(env, jpath);
        }
        break;
    }
    case UI_PROP_WEBVIEW_URL: {
        LOGI("setStrProp(node=%d, webviewUrl=\"%s\")", nodeId, value);
        if ((*env)->IsInstanceOf(env, view, g_class_WebView)) {
            jstring jurl = (*env)->NewStringUTF(env, value);
            (*env)->CallVoidMethod(env, view, g_method_loadUrl, jurl);
            (*env)->DeleteLocalRef(env, jurl);
        }
        break;
    }
    default:
        LOGI("setStrProp: unknown propId %d", propId);
        break;
    }
}

static void android_set_num_prop(int32_t nodeId, int32_t propId, double value)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;

    switch (propId) {
    case UI_PROP_FONT_SIZE:
        /* setTextSize only makes sense on TextView subclasses */
        if ((*env)->IsInstanceOf(env, view, g_class_TextView)) {
            (*env)->CallVoidMethod(env, view, g_method_setTextSize, (jfloat)value);
            LOGI("setNumProp(node=%d, fontSize=%.1f)", nodeId, value);
        } else {
            LOGI("setNumProp: fontSize ignored on non-TextView node=%d", nodeId);
        }
        break;
    case UI_PROP_PADDING: {
        jint px = (jint)value;
        (*env)->CallVoidMethod(env, view, g_method_setPadding, px, px, px, px);
        LOGI("setNumProp(node=%d, padding=%d)", nodeId, px);
        break;
    }
    case UI_PROP_INPUT_TYPE: {
        /* Haskell 0 = InputText  -> Android TYPE_CLASS_TEXT           (1)
         * Haskell 1 = InputNumber -> Android TYPE_CLASS_NUMBER |
         *                            TYPE_NUMBER_FLAG_DECIMAL         (8194)
         */
        jint androidType;
        if ((int)value == 1) {
            androidType = 8194; /* TYPE_CLASS_NUMBER | TYPE_NUMBER_FLAG_DECIMAL */
        } else {
            androidType = 1;    /* TYPE_CLASS_TEXT */
        }
        (*env)->CallVoidMethod(env, view, g_method_setInputType, androidType);
        LOGI("setNumProp(node=%d, inputType=%d, android=%d)", nodeId, (int)value, androidType);
        break;
    }
    case UI_PROP_GRAVITY: {
        /* Haskell 0 = AlignStart  -> Gravity.START              (0x00800003)
         * Haskell 1 = AlignCenter -> Gravity.CENTER_HORIZONTAL  (1)
         * Haskell 2 = AlignEnd    -> Gravity.END                (0x00800005)
         */
        jint gravity;
        switch ((int)value) {
        case 1:  gravity = 1;          break; /* CENTER_HORIZONTAL */
        case 2:  gravity = 0x00800005; break; /* END */
        default: gravity = 0x00800003; break; /* START */
        }
        if ((*env)->IsInstanceOf(env, view, g_class_TextView)) {
            (*env)->CallVoidMethod(env, view, g_method_setGravity_TextView, gravity);
            /* Set width to MATCH_PARENT so gravity has room to take effect */
            jobject layoutParams = (*env)->NewObject(env,
                g_class_ViewGroup_LayoutParams, g_ctor_ViewGroup_LayoutParams,
                (jint)-1, (jint)-2); /* MATCH_PARENT, WRAP_CONTENT */
            (*env)->CallVoidMethod(env, view, g_method_setLayoutParams, layoutParams);
            (*env)->DeleteLocalRef(env, layoutParams);
        } else if ((*env)->IsInstanceOf(env, view, g_class_LinearLayout)) {
            (*env)->CallVoidMethod(env, view, g_method_setGravity_LinearLayout, gravity);
        }
        LOGI("setNumProp(node=%d, gravity=%d)", nodeId, gravity);
        break;
    }
    case UI_PROP_SCALE_TYPE: {
        /* Haskell 0 = ScaleFit  -> FIT_CENTER
         * Haskell 1 = ScaleFill -> CENTER_CROP
         * Haskell 2 = ScaleNone -> CENTER
         */
        if ((*env)->IsInstanceOf(env, view, g_class_ImageView)) {
            jclass scaleTypeClass = (*env)->FindClass(env, "android/widget/ImageView$ScaleType");
            const char *fieldName;
            switch ((int)value) {
            case 1:  fieldName = "CENTER_CROP"; break;
            case 2:  fieldName = "CENTER";      break;
            default: fieldName = "FIT_CENTER";  break;
            }
            jfieldID field = (*env)->GetStaticFieldID(env, scaleTypeClass,
                fieldName, "Landroid/widget/ImageView$ScaleType;");
            jobject scaleType = (*env)->GetStaticObjectField(env, scaleTypeClass, field);
            (*env)->CallVoidMethod(env, view, g_method_setScaleType, scaleType);
            (*env)->DeleteLocalRef(env, scaleType);
            (*env)->DeleteLocalRef(env, scaleTypeClass);
        }
        LOGI("setNumProp(node=%d, scaleType=%d)", nodeId, (int)value);
        break;
    }
    case UI_PROP_MAP_LAT:
    case UI_PROP_MAP_LON:
    case UI_PROP_MAP_ZOOM: {
        /* Update placeholder label inside the FrameLayout with new coordinates.
         * The FrameLayout's first child is the placeholder TextView. */
        if ((*env)->IsInstanceOf(env, view, g_class_FrameLayout)) {
            jmethodID getChildAt = (*env)->GetMethodID(env, g_class_ViewGroup,
                "getChildAt", "(I)Landroid/view/View;");
            jobject child = (*env)->CallObjectMethod(env, view, getChildAt, (jint)0);
            if (child && (*env)->IsInstanceOf(env, child, g_class_TextView)) {
                char buf[128];
                snprintf(buf, sizeof(buf), "Map placeholder (%.4f, %.4f) z%.1f",
                         value, value, value);
                jstring jtext = (*env)->NewStringUTF(env, buf);
                (*env)->CallVoidMethod(env, child, g_method_setText, jtext);
                (*env)->DeleteLocalRef(env, jtext);
            }
            if (child) (*env)->DeleteLocalRef(env, child);
        }
        LOGI("setNumProp(node=%d, mapProp=%d, value=%.4f)", nodeId, propId, value);
        break;
    }
    case UI_PROP_MAP_SHOW_USER_LOC:
        /* No-op for placeholder — real map would toggle location layer */
        LOGI("setNumProp(node=%d, showUserLoc=%.0f)", nodeId, value);
        break;
    default:
        LOGI("setNumProp: unknown propId %d", propId);
        break;
    }
}

static void android_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;
    if (!(*env)->IsInstanceOf(env, view, g_class_ImageView)) return;

    /* Create Java byte[] and copy data */
    jbyteArray jdata = (*env)->NewByteArray(env, length);
    (*env)->SetByteArrayRegion(env, jdata, 0, length, (const jbyte *)data);

    /* BitmapFactory.decodeByteArray(byte[], offset, length) */
    jobject bitmap = (*env)->CallStaticObjectMethod(env,
        g_class_BitmapFactory, g_method_decodeByteArray, jdata, (jint)0, (jint)length);
    if (bitmap) {
        (*env)->CallVoidMethod(env, view, g_method_setImageBitmap, bitmap);
        (*env)->DeleteLocalRef(env, bitmap);
    } else {
        LOGE("setImageData: BitmapFactory.decodeByteArray failed (node=%d, %d bytes)", nodeId, length);
    }
    (*env)->DeleteLocalRef(env, jdata);

    LOGI("setImageData(node=%d, %d bytes)", nodeId, length);
}

static void android_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;

    /* Store callbackId as the view's tag (Integer) */
    jobject tagObj = (*env)->NewObject(env, g_class_Integer, g_ctor_Integer, callbackId);
    (*env)->CallVoidMethod(env, view, g_method_setTag, tagObj);
    (*env)->DeleteLocalRef(env, tagObj);

    switch (eventType) {
    case UI_EVENT_CLICK:
        if ((*env)->IsInstanceOf(env, view, g_class_WebView)) {
            /* Register a WebViewClient via our Java helper for page-load callbacks */
            if (g_method_registerWebViewClient) {
                (*env)->CallVoidMethod(env, g_activity, g_method_registerWebViewClient, view);
                LOGI("setHandler(node=%d, webview-pageload, callback=%d)", nodeId, callbackId);
            } else {
                LOGE("setHandler: registerWebViewClient unavailable, skipping node=%d", nodeId);
            }
        } else {
            /* Register the Activity (which implements OnClickListener) as handler */
            (*env)->CallVoidMethod(env, view, g_method_setOnClickListener, g_activity);
        }
        LOGI("setHandler(node=%d, click, callback=%d)", nodeId, callbackId);
        break;
    case UI_EVENT_TEXT_CHANGE:
        if ((*env)->IsInstanceOf(env, view, g_class_FrameLayout)) {
            /* MapView placeholder: callbackId stored in tag, no TextWatcher needed */
            LOGI("setHandler(node=%d, mapRegionChange, callback=%d)", nodeId, callbackId);
        } else if (g_method_registerTextWatcher) {
            /* Register a TextWatcher via our Java helper */
            (*env)->CallVoidMethod(env, g_activity, g_method_registerTextWatcher, view);
            LOGI("setHandler(node=%d, textChange, callback=%d)", nodeId, callbackId);
        } else {
            LOGE("setHandler: registerTextWatcher unavailable, skipping node=%d", nodeId);
        }
        break;
    default:
        LOGI("setHandler: unknown eventType %d", eventType);
        break;
    }
}

static void android_add_child(int32_t parentId, int32_t childId)
{
    JNIEnv *env = g_env;
    jobject parent = get_node(parentId);
    jobject child  = get_node(childId);
    if (!parent || !child) return;

    (*env)->CallVoidMethod(env, parent, g_method_addView, child);
}

static void android_remove_child(int32_t parentId, int32_t childId)
{
    JNIEnv *env = g_env;
    jobject parent = get_node(parentId);
    jobject child  = get_node(childId);
    if (!parent || !child) return;

    (*env)->CallVoidMethod(env, parent, g_method_removeView, child);
}

static void android_destroy_node(int32_t nodeId)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;

    (*env)->DeleteGlobalRef(env, view);
    g_nodes[nodeId] = NULL;
}

static void android_set_root(int32_t nodeId)
{
    JNIEnv *env = g_env;
    jobject view = get_node(nodeId);
    if (!view) return;

    (*env)->CallVoidMethod(env, g_activity, g_method_setContentView, view);
    LOGI("setRoot(node=%d)", nodeId);
}

static void android_clear(void)
{
    JNIEnv *env = g_env;
    for (int i = 1; i < g_next_node_id; i++) {
        if (g_nodes[i]) {
            (*env)->DeleteGlobalRef(env, g_nodes[i]);
            g_nodes[i] = NULL;
        }
    }
    g_next_node_id = 1;
    /* Dynamic mode: keep the allocation to avoid malloc/free churn each frame.
     * Static mode: nothing extra to do — array is stack-allocated. */
    LOGI("clear()");
}

/* ---- Public API ---- */

/*
 * Set up the Android UI bridge. Called from Java before haskellRenderUI.
 * Resolves JNI IDs and registers callbacks with the platform-agnostic
 * dispatcher.
 */
void setup_android_ui_bridge(JNIEnv *env, jobject activity, void *haskellCtx)
{
    g_env = env;
    g_activity = (*env)->NewGlobalRef(env, activity);
    (void)haskellCtx; /* context is now owned by jni_bridge.c */

#ifdef DYNAMIC_NODE_POOL
    if (!g_nodes) {
        g_pool_capacity = INITIAL_POOL_SIZE;
        g_nodes = calloc((size_t)g_pool_capacity, sizeof(jobject));
    } else {
        memset(g_nodes, 0, (size_t)g_pool_capacity * sizeof(jobject));
    }
#else
    memset(g_nodes, 0, sizeof(g_nodes));
#endif
    g_next_node_id = 1;

    if (resolve_jni_ids(env, activity) != 0) {
        LOGE("Failed to resolve JNI IDs for UI bridge");
        return;
    }

    ui_register_callbacks(&g_android_callbacks);
    LOGI("Android UI bridge initialized");
}

/*
 * Handle a click event from Java. Looks up the callbackId from the
 * view's tag and dispatches to Haskell.
 */
void android_handle_click(JNIEnv *env, jobject view, void *haskellCtx)
{
    /* Update g_env in case we're called from a different JNI attach */
    g_env = env;

    jobject tagObj = (*env)->CallObjectMethod(env, view, g_method_getTag);
    if (!tagObj) {
        LOGI("Click on view with no tag — ignoring");
        return;
    }

    jint callbackId = (*env)->CallIntMethod(env, tagObj, g_method_intValue);
    (*env)->DeleteLocalRef(env, tagObj);

    LOGI("Click dispatched: callbackId=%d", callbackId);
    haskellOnUIEvent(haskellCtx, callbackId);
}

/*
 * Handle a text change event from Java. Looks up the callbackId from
 * the view's tag and dispatches to Haskell with the new text.
 * Does NOT trigger a re-render (avoids EditText cursor/flicker).
 */
void android_handle_text_change(JNIEnv *env, jobject view, jstring text, void *haskellCtx)
{
    g_env = env;

    jobject tagObj = (*env)->CallObjectMethod(env, view, g_method_getTag);
    if (!tagObj) {
        LOGI("Text change on view with no tag — ignoring");
        return;
    }

    jint callbackId = (*env)->CallIntMethod(env, tagObj, g_method_intValue);
    (*env)->DeleteLocalRef(env, tagObj);

    const char *ctext = (*env)->GetStringUTFChars(env, text, NULL);
    if (!ctext) return;

    LOGI("Text change dispatched: callbackId=%d, text=\"%s\"", callbackId, ctext);
    haskellOnUITextChange(haskellCtx, callbackId, ctext);

    (*env)->ReleaseStringUTFChars(env, text, ctext);
}
