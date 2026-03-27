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

/* Maximum number of native views we can hold at once.
 * Re-renders clear all nodes, so this only bounds a single frame. */
#define MAX_NODES 256

/* Haskell FFI exports (declared here since this file is compiled by NDK) */
extern void haskellOnUIEvent(void *ctx, int callbackId);
extern void haskellOnUITextChange(void *ctx, int callbackId, const char *text);

/* ---- Global state (valid only on the UI thread) ---- */
static JNIEnv  *g_env      = NULL;
static jobject  g_activity  = NULL;   /* global ref to Activity */
static void    *g_haskell_ctx = NULL; /* opaque Haskell context */

/* Node pool: indexed by nodeId (1-based, 0 = invalid) */
static jobject  g_nodes[MAX_NODES];
static int32_t  g_next_node_id = 1;

/* ---- Per-button callback IDs stored as view tags ---- */

/* Cached JNI class/method IDs (resolved once in setup) */
static jclass   g_class_TextView;
static jclass   g_class_Button;
static jclass   g_class_EditText;
static jclass   g_class_LinearLayout;
static jclass   g_class_ViewGroup;
static jclass   g_class_ViewGroup_LayoutParams;
static jclass   g_class_Integer;

static jmethodID g_ctor_TextView;
static jmethodID g_ctor_Button;
static jmethodID g_ctor_EditText;
static jmethodID g_ctor_LinearLayout;
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

/* LinearLayout orientation constants */
static jint ORIENTATION_VERTICAL   = 1;
static jint ORIENTATION_HORIZONTAL = 0;

/* ---- Forward declarations ---- */
static int32_t android_create_node(int32_t nodeType);
static void    android_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
static void    android_set_num_prop(int32_t nodeId, int32_t propId, double value);
static void    android_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
static void    android_add_child(int32_t parentId, int32_t childId);
static void    android_remove_child(int32_t parentId, int32_t childId);
static void    android_destroy_node(int32_t nodeId);
static void    android_set_root(int32_t nodeId);
static void    android_clear(void);

static UIBridgeCallbacks g_android_callbacks = {
    .createNode  = android_create_node,
    .setStrProp  = android_set_str_prop,
    .setNumProp  = android_set_num_prop,
    .setHandler  = android_set_handler,
    .addChild    = android_add_child,
    .removeChild = android_remove_child,
    .destroyNode = android_destroy_node,
    .setRoot     = android_set_root,
    .clear       = android_clear,
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

    return 0;
}

/* ---- Node pool helpers ---- */
static jobject get_node(int32_t nodeId)
{
    if (nodeId < 1 || nodeId >= MAX_NODES) return NULL;
    return g_nodes[nodeId];
}

/* ---- Callback implementation ---- */

static int32_t android_create_node(int32_t nodeType)
{
    if (g_next_node_id >= MAX_NODES) {
        LOGE("Node pool exhausted (max %d)", MAX_NODES);
        return 0;
    }

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
    default:
        LOGI("setStrProp: unknown propId %d", propId);
        break;
    }
}

static void android_set_num_prop(int32_t nodeId, int32_t propId, double value)
{
    /* TODO: Implement font size, padding, etc. */
    LOGI("setNumProp(node=%d, prop=%d, value=%.2f) — not yet implemented", nodeId, propId, value);
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
        /* Register the Activity (which implements OnClickListener) as handler */
        (*env)->CallVoidMethod(env, view, g_method_setOnClickListener, g_activity);
        LOGI("setHandler(node=%d, click, callback=%d)", nodeId, callbackId);
        break;
    case UI_EVENT_TEXT_CHANGE:
        /* Register a TextWatcher via our Java helper */
        (*env)->CallVoidMethod(env, g_activity, g_method_registerTextWatcher, view);
        LOGI("setHandler(node=%d, textChange, callback=%d)", nodeId, callbackId);
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
    g_haskell_ctx = haskellCtx;

    memset(g_nodes, 0, sizeof(g_nodes));
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
void android_handle_click(JNIEnv *env, jobject view)
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
    haskellOnUIEvent(g_haskell_ctx, callbackId);
}

/*
 * Handle a text change event from Java. Looks up the callbackId from
 * the view's tag and dispatches to Haskell with the new text.
 * Does NOT trigger a re-render (avoids EditText cursor/flicker).
 */
void android_handle_text_change(JNIEnv *env, jobject view, jstring text)
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
    haskellOnUITextChange(g_haskell_ctx, callbackId, ctext);

    (*env)->ReleaseStringUTFChars(env, text, ctext);
}
