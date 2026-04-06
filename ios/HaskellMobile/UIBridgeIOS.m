/*
 * iOS implementation of the UI bridge callbacks.
 *
 * Uses UIKit to create iOS views (UILabel, UIButton, UIStackView)
 * and manage the view hierarchy. Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread — the same thread that
 * calls haskellRenderUI from Swift.
 */

#import <UIKit/UIKit.h>
#import <os/log.h>
#include <stdlib.h>
#include <string.h>
#include "UIBridge.h"

#define LOG_TAG "UIBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Maximum number of native views we can hold at once.
 * Re-renders clear all nodes, so this only bounds a single frame. */
#define MAX_NODES 256

/* Haskell FFI exports (declared here since this file is compiled by Xcode) */
extern void haskellOnUIEvent(void *ctx, int callbackId);

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (HaskellMobile.Locale) */
extern void haskellLogLocale(void);

/* ---- Global state (valid only on the main thread) ---- */
static UIViewController *g_viewController = nil;
static void             *g_haskell_ctx    = NULL;

/* Node pool: indexed by nodeId (1-based, 0 = invalid) */
static __strong UIView *g_nodes[MAX_NODES];
static int32_t          g_next_node_id = 1;

/* For ScrollView nodes: the inner UIStackView that holds children */
static __strong UIView *g_content_views[MAX_NODES];

/* ---- Singleton handler for button taps ---- */
@interface IOSBridgeHandler : NSObject
+ (instancetype)shared;
- (void)handleTap:(UIButton *)sender;
@end

@implementation IOSBridgeHandler

+ (instancetype)shared {
    static IOSBridgeHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IOSBridgeHandler alloc] init];
    });
    return instance;
}

- (void)handleTap:(UIButton *)sender {
    int32_t callbackId = (int32_t)sender.tag;
    LOGI("Click dispatched: callbackId=%d", callbackId);
    haskellOnUIEvent(g_haskell_ctx, callbackId);
}

@end

/* ---- Node pool helpers ---- */
static UIView *get_node(int32_t nodeId)
{
    if (nodeId < 1 || nodeId >= MAX_NODES) return nil;
    return g_nodes[nodeId];
}

/* ---- Forward declarations ---- */
static int32_t ios_create_node(int32_t nodeType);
static void    ios_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
static void    ios_set_num_prop(int32_t nodeId, int32_t propId, double value);
static void    ios_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
static void    ios_add_child(int32_t parentId, int32_t childId);
static void    ios_remove_child(int32_t parentId, int32_t childId);
static void    ios_destroy_node(int32_t nodeId);
static void    ios_set_root(int32_t nodeId);
static void    ios_clear(void);

static UIBridgeCallbacks g_ios_callbacks = {
    .createNode  = ios_create_node,
    .setStrProp  = ios_set_str_prop,
    .setNumProp  = ios_set_num_prop,
    .setHandler  = ios_set_handler,
    .addChild    = ios_add_child,
    .removeChild = ios_remove_child,
    .destroyNode = ios_destroy_node,
    .setRoot     = ios_set_root,
    .clear       = ios_clear,
};

/* ---- Callback implementation ---- */

static int32_t ios_create_node(int32_t nodeType)
{
    if (g_next_node_id >= MAX_NODES) {
        LOGE("Node pool exhausted (max %d)", MAX_NODES);
        return 0;
    }

    UIView *view = nil;

    switch (nodeType) {
    case UI_NODE_TEXT: {
        UILabel *label = [[UILabel alloc] init];
        label.textAlignment = NSTextAlignmentCenter;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        view = label;
        break;
    }
    case UI_NODE_BUTTON: {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button addTarget:[IOSBridgeHandler shared]
                   action:@selector(handleTap:)
         forControlEvents:UIControlEventTouchUpInside];
        view = button;
        break;
    }
    case UI_NODE_COLUMN: {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        view = stack;
        break;
    }
    case UI_NODE_ROW: {
        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        view = stack;
        break;
    }
    case UI_NODE_SCROLL_VIEW: {
        UIScrollView *scrollView = [[UIScrollView alloc] init];
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        /* Inner content stack — children are added here, not into scrollView directly */
        UIStackView *contentStack = [[UIStackView alloc] init];
        contentStack.axis = UILayoutConstraintAxisVertical;
        contentStack.alignment = UIStackViewAlignmentFill;
        contentStack.spacing = 0;
        contentStack.translatesAutoresizingMaskIntoConstraints = NO;
        [scrollView addSubview:contentStack];
        UILayoutGuide *contentGuide = scrollView.contentLayoutGuide;
        UILayoutGuide *frameGuide   = scrollView.frameLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [contentStack.topAnchor     constraintEqualToAnchor:contentGuide.topAnchor],
            [contentStack.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
            [contentStack.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
            [contentStack.bottomAnchor  constraintEqualToAnchor:contentGuide.bottomAnchor],
            [contentStack.widthAnchor   constraintEqualToAnchor:frameGuide.widthAnchor],
        ]];
        int32_t nodeId = g_next_node_id++;
        g_nodes[nodeId]        = scrollView;
        g_content_views[nodeId] = contentStack;
        LOGI("createNode(type=%d) -> %d", nodeType, nodeId);
        return nodeId;
    }
    default:
        LOGE("Unknown node type: %d", nodeType);
        return 0;
    }

    int32_t nodeId = g_next_node_id++;
    g_nodes[nodeId] = view;

    LOGI("createNode(type=%d) -> %d", nodeType, nodeId);
    return nodeId;
}

static void ios_set_str_prop(int32_t nodeId, int32_t propId, const char *value)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    NSString *str = [NSString stringWithUTF8String:value];

    switch (propId) {
    case UI_PROP_TEXT:
        LOGI("setStrProp(node=%d, text=\"%{public}s\")", nodeId, value);
        if ([view isKindOfClass:[UILabel class]]) {
            ((UILabel *)view).text = str;
        } else if ([view isKindOfClass:[UIButton class]]) {
            [((UIButton *)view) setTitle:str forState:UIControlStateNormal];
        }
        break;
    default:
        LOGI("setStrProp: unknown propId %d", propId);
        break;
    }
}

static void ios_set_num_prop(int32_t nodeId, int32_t propId, double value)
{
    /* TODO: Implement font size, padding, etc. */
    LOGI("setNumProp(node=%d, prop=%d, value=%.2f) — not yet implemented", nodeId, propId, value);
}

static void ios_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    if (eventType != UI_EVENT_CLICK) {
        LOGI("setHandler: unknown eventType %d", eventType);
        return;
    }

    /* Store callbackId in the view's tag property */
    view.tag = callbackId;

    LOGI("setHandler(node=%d, click, callback=%d)", nodeId, callbackId);
}

static void ios_add_child(int32_t parentId, int32_t childId)
{
    UIView *parent = get_node(parentId);
    UIView *child  = get_node(childId);
    if (!parent || !child) return;

    /* For ScrollView nodes, children go into the content stack, not the scroll view itself */
    UIView *addTarget = g_content_views[parentId] ? g_content_views[parentId] : parent;
    if ([addTarget isKindOfClass:[UIStackView class]]) {
        [(UIStackView *)addTarget addArrangedSubview:child];
    } else {
        [addTarget addSubview:child];
    }
}

static void ios_remove_child(int32_t parentId, int32_t childId)
{
    UIView *parent = get_node(parentId);
    UIView *child  = get_node(childId);
    if (!parent || !child) return;

    if ([parent isKindOfClass:[UIStackView class]]) {
        [(UIStackView *)parent removeArrangedSubview:child];
    }
    [child removeFromSuperview];
}

static void ios_destroy_node(int32_t nodeId)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    [view removeFromSuperview];
    g_nodes[nodeId] = nil;
}

static void ios_set_root(int32_t nodeId)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    UIView *container = g_viewController.view;

    /* Remove any previously set root views (but keep the container) */
    for (UIView *sub in container.subviews) {
        [sub removeFromSuperview];
    }

    [container addSubview:view];

    /* Pin root view to fill the safe area / full screen.
     * Using fill instead of center lets ScrollView expand to the full viewport. */
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor      constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor],
        [view.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [view.bottomAnchor   constraintEqualToAnchor:container.bottomAnchor],
    ]];

    LOGI("setRoot(node=%d)", nodeId);
}

static void ios_clear(void)
{
    for (int i = 1; i < g_next_node_id; i++) {
        if (g_nodes[i]) {
            [g_nodes[i] removeFromSuperview];
            g_nodes[i] = nil;
        }
    }
    g_next_node_id = 1;
    memset(g_content_views, 0, sizeof(g_content_views));
    LOGI("clear()");
}

/* ---- Public API ---- */

/*
 * Set up the iOS UI bridge. Called from Swift before haskellRenderUI.
 * Registers callbacks with the platform-agnostic dispatcher.
 *
 * viewController: opaque pointer to the UIViewController (cast from Swift)
 * haskellCtx:     opaque Haskell context pointer
 */
void setup_ios_ui_bridge(void *viewController, void *haskellCtx)
{
    g_log = os_log_create("me.jappie.haskellmobile", LOG_TAG);

    g_viewController = (__bridge UIViewController *)viewController;
    g_haskell_ctx = haskellCtx;

    memset(g_nodes, 0, sizeof(g_nodes));
    memset(g_content_views, 0, sizeof(g_content_views));
    g_next_node_id = 1;

    ui_register_callbacks(&g_ios_callbacks);
    LOGI("iOS UI bridge initialized");

    /* Cache the system locale from NSLocale.currentLocale */
    {
        NSString *lang = [[NSLocale currentLocale] languageCode];
        NSString *region = [[NSLocale currentLocale] countryCode];
        NSString *tag = region
            ? [NSString stringWithFormat:@"%@-%@", lang, region]
            : lang;
        setSystemLocale(strdup([tag UTF8String]));
        haskellLogLocale();
    }
}
