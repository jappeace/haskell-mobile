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

/* --- Node pool configuration ---
 *
 * Two compile-time flags control the pool strategy:
 *   -DMAX_NODES=N         Override the static pool size (default 256).
 *   -DDYNAMIC_NODE_POOL   Use malloc/realloc; MAX_NODES is ignored.
 *
 * Re-renders clear all nodes, so the pool only bounds a single frame. */
#ifdef DYNAMIC_NODE_POOL
  static __strong UIView **g_nodes         = NULL;
  static __strong UIView **g_content_views = NULL;
  static int32_t  g_pool_capacity = 0;
  #define INITIAL_POOL_SIZE 256
#else
  #ifndef MAX_NODES
  #define MAX_NODES 256
  #endif
  static __strong UIView *g_nodes[MAX_NODES];
  static __strong UIView *g_content_views[MAX_NODES];
#endif
static int32_t g_next_node_id = 1;

/* Haskell FFI exports (declared here since this file is compiled by Xcode) */
extern void haskellOnUIEvent(void *ctx, int callbackId);
extern void haskellOnUITextChange(void *ctx, int callbackId, const char *text);

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (HaskellMobile.Locale) */
extern void haskellLogLocale(void);

/* ---- Global state (valid only on the main thread) ---- */
static UIViewController *g_viewController = nil;

/* ---- Singleton handler for button taps ---- */
@interface IOSBridgeHandler : NSObject
@property (nonatomic, assign) void *haskellCtx;
+ (instancetype)shared;
- (void)handleTap:(UIButton *)sender;
- (void)handleTextChange:(UITextField *)sender;
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
    haskellOnUIEvent(self.haskellCtx, callbackId);
}

- (void)handleTextChange:(UITextField *)sender {
    int32_t callbackId = (int32_t)sender.tag;
    NSString *text = sender.text ?: @"";
    LOGI("TextChange dispatched: callbackId=%d text=\"%{public}s\"", callbackId, [text UTF8String]);
    haskellOnUITextChange(self.haskellCtx, callbackId, [text UTF8String]);
}

@end

/* ---- Node pool helpers ---- */

#ifdef DYNAMIC_NODE_POOL
/* Grow both pools so that nodeId < g_pool_capacity.
 * ARC pointers: allocate new array with calloc (nil-init), copy old
 * pointers, free old array.  ARC retains are on the individual view
 * assignments, not the array allocation itself. */
static int ensure_pool_capacity(int32_t needed)
{
    if (needed < g_pool_capacity) return 0;
    int32_t new_cap = g_pool_capacity ? g_pool_capacity : INITIAL_POOL_SIZE;
    while (new_cap <= needed) new_cap *= 2;

    __strong UIView **new_nodes = (__strong UIView **)calloc((size_t)new_cap, sizeof(UIView *));
    __strong UIView **new_content = (__strong UIView **)calloc((size_t)new_cap, sizeof(UIView *));
    if (!new_nodes || !new_content) {
        LOGE("Node pool calloc failed (requested %d slots)", new_cap);
        free(new_nodes);
        free(new_content);
        return -1;
    }
    if (g_nodes) {
        memcpy(new_nodes, g_nodes, (size_t)g_pool_capacity * sizeof(UIView *));
        free(g_nodes);
    }
    if (g_content_views) {
        memcpy(new_content, g_content_views, (size_t)g_pool_capacity * sizeof(UIView *));
        free(g_content_views);
    }
    g_nodes = new_nodes;
    g_content_views = new_content;
    g_pool_capacity = new_cap;
    return 0;
}
#endif

static UIView *get_node(int32_t nodeId)
{
#ifdef DYNAMIC_NODE_POOL
    if (nodeId < 1 || nodeId >= g_pool_capacity) return nil;
#else
    if (nodeId < 1 || nodeId >= MAX_NODES) return nil;
#endif
    return g_nodes[nodeId];
}

/* ---- Forward declarations ---- */
static int32_t ios_create_node(int32_t nodeType);
static void    ios_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
static void    ios_set_num_prop(int32_t nodeId, int32_t propId, double value);
static void    ios_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length);
static void    ios_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
static void    ios_add_child(int32_t parentId, int32_t childId);
static void    ios_remove_child(int32_t parentId, int32_t childId);
static void    ios_destroy_node(int32_t nodeId);
static void    ios_set_root(int32_t nodeId);
static void    ios_clear(void);

static UIBridgeCallbacks g_ios_callbacks = {
    .createNode   = ios_create_node,
    .setStrProp   = ios_set_str_prop,
    .setNumProp   = ios_set_num_prop,
    .setImageData = ios_set_image_data,
    .setHandler   = ios_set_handler,
    .addChild     = ios_add_child,
    .removeChild  = ios_remove_child,
    .destroyNode  = ios_destroy_node,
    .setRoot      = ios_set_root,
    .clear        = ios_clear,
};

/* ---- Hex color parser ---- */

/*
 * Parse a hex color string (#RGB, #RRGGBB, or #AARRGGBB) into a UIColor.
 * Returns nil on invalid input.
 */
static UIColor *parse_hex_color(const char *hex)
{
    if (!hex || hex[0] != '#') return nil;
    NSString *digits = [NSString stringWithUTF8String:hex + 1];
    unsigned int raw = 0;
    NSScanner *scanner = [NSScanner scannerWithString:digits];
    if (![scanner scanHexInt:&raw]) return nil;

    CGFloat alpha, red, green, blue;
    switch (digits.length) {
    case 3: {
        /* #RGB -> expand each nibble */
        unsigned int r = (raw >> 8) & 0xF;
        unsigned int g = (raw >> 4) & 0xF;
        unsigned int b = raw & 0xF;
        alpha = 1.0;
        red   = (r * 0x11) / 255.0;
        green = (g * 0x11) / 255.0;
        blue  = (b * 0x11) / 255.0;
        break;
    }
    case 6:
        /* #RRGGBB */
        alpha = 1.0;
        red   = ((raw >> 16) & 0xFF) / 255.0;
        green = ((raw >> 8) & 0xFF) / 255.0;
        blue  = (raw & 0xFF) / 255.0;
        break;
    case 8:
        /* #AARRGGBB */
        alpha = ((raw >> 24) & 0xFF) / 255.0;
        red   = ((raw >> 16) & 0xFF) / 255.0;
        green = ((raw >> 8) & 0xFF) / 255.0;
        blue  = (raw & 0xFF) / 255.0;
        break;
    default:
        return nil;
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

/* ---- Callback implementation ---- */

static int32_t ios_create_node(int32_t nodeType)
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
    case UI_NODE_TEXT_INPUT: {
        UITextField *textField = [[UITextField alloc] init];
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        view = textField;
        break;
    }
    case UI_NODE_IMAGE: {
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        view = imageView;
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
        } else if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).text = str;
        }
        break;
    case UI_PROP_HINT:
        LOGI("setStrProp(node=%d, hint=\"%{public}s\")", nodeId, value);
        if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).placeholder = str;
        }
        break;
    case UI_PROP_COLOR: {
        LOGI("setStrProp(node=%d, color=\"%{public}s\")", nodeId, value);
        UIColor *color = parse_hex_color(value);
        if (!color) break;
        if ([view isKindOfClass:[UILabel class]]) {
            ((UILabel *)view).textColor = color;
        } else if ([view isKindOfClass:[UIButton class]]) {
            [((UIButton *)view) setTitleColor:color forState:UIControlStateNormal];
        } else if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).textColor = color;
        }
        break;
    }
    case UI_PROP_BG_COLOR: {
        LOGI("setStrProp(node=%d, bgColor=\"%{public}s\")", nodeId, value);
        UIColor *color = parse_hex_color(value);
        if (!color) break;
        view.backgroundColor = color;
        break;
    }
    case UI_PROP_IMAGE_RESOURCE: {
        LOGI("setStrProp(node=%d, imageResource=\"%{public}s\")", nodeId, value);
        if ([view isKindOfClass:[UIImageView class]]) {
            UIImage *image = [UIImage imageNamed:str];
            if (image) {
                ((UIImageView *)view).image = image;
            } else {
                LOGE("Image resource not found: %{public}s", value);
            }
        }
        break;
    }
    case UI_PROP_IMAGE_FILE: {
        LOGI("setStrProp(node=%d, imageFile=\"%{public}s\")", nodeId, value);
        if ([view isKindOfClass:[UIImageView class]]) {
            UIImage *image = [UIImage imageWithContentsOfFile:str];
            if (image) {
                ((UIImageView *)view).image = image;
            } else {
                LOGE("Failed to load image file: %{public}s", value);
            }
        }
        break;
    }
    default:
        LOGI("setStrProp: unknown propId %d", propId);
        break;
    }
}

static void ios_set_num_prop(int32_t nodeId, int32_t propId, double value)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    switch (propId) {
    case UI_PROP_FONT_SIZE: {
        UIFont *font = [UIFont systemFontOfSize:(CGFloat)value];
        if ([view isKindOfClass:[UILabel class]]) {
            ((UILabel *)view).font = font;
        } else if ([view isKindOfClass:[UIButton class]]) {
            ((UIButton *)view).titleLabel.font = font;
        } else if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).font = font;
        } else {
            LOGI("setNumProp: fontSize ignored on non-text node=%d", nodeId);
            break;
        }
        LOGI("setNumProp(node=%d, fontSize=%.1f)", nodeId, value);
        break;
    }
    case UI_PROP_INPUT_TYPE: {
        int inputType = (int)value;
        if ([view isKindOfClass:[UITextField class]]) {
            UIKeyboardType kbType;
            switch (inputType) {
            case 1:  kbType = UIKeyboardTypeDecimalPad; break;
            default: kbType = UIKeyboardTypeDefault;    break;
            }
            ((UITextField *)view).keyboardType = kbType;
        }
        LOGI("setNumProp(node=%d, inputType=%d)", nodeId, inputType);
        break;
    }
    case UI_PROP_PADDING: {
        CGFloat pt = (CGFloat)value;
        view.layoutMargins = UIEdgeInsetsMake(pt, pt, pt, pt);
        LOGI("setNumProp(node=%d, padding=%.1f)", nodeId, value);
        break;
    }
    case UI_PROP_SCALE_TYPE: {
        /* Haskell 0 = ScaleFit, 1 = ScaleFill, 2 = ScaleNone */
        if ([view isKindOfClass:[UIImageView class]]) {
            UIViewContentMode mode;
            switch ((int)value) {
            case 1:  mode = UIViewContentModeScaleAspectFill; break;
            case 2:  mode = UIViewContentModeCenter;          break;
            default: mode = UIViewContentModeScaleAspectFit;  break;
            }
            ((UIImageView *)view).contentMode = mode;
        }
        LOGI("setNumProp(node=%d, scaleType=%d)", nodeId, (int)value);
        break;
    }
    case UI_PROP_GRAVITY: {
        /* Haskell 0 = AlignStart, 1 = AlignCenter, 2 = AlignEnd */
        int gravity = (int)value;
        if ([view isKindOfClass:[UILabel class]]) {
            NSTextAlignment align;
            switch (gravity) {
            case 1:  align = NSTextAlignmentCenter; break;
            case 2:  align = NSTextAlignmentRight;  break;
            default: align = NSTextAlignmentLeft;   break;
            }
            ((UILabel *)view).textAlignment = align;
        } else if ([view isKindOfClass:[UIButton class]]) {
            UIControlContentHorizontalAlignment align;
            switch (gravity) {
            case 1:  align = UIControlContentHorizontalAlignmentCenter;  break;
            case 2:  align = UIControlContentHorizontalAlignmentTrailing; break;
            default: align = UIControlContentHorizontalAlignmentLeading;  break;
            }
            ((UIButton *)view).contentHorizontalAlignment = align;
        } else if ([view isKindOfClass:[UIStackView class]]) {
            UIStackViewAlignment align;
            switch (gravity) {
            case 1:  align = UIStackViewAlignmentCenter;  break;
            case 2:  align = UIStackViewAlignmentTrailing; break;
            default: align = UIStackViewAlignmentLeading;  break;
            }
            ((UIStackView *)view).alignment = align;
        }
        LOGI("setNumProp(node=%d, gravity=%d)", nodeId, gravity);
        break;
    }
    default:
        LOGI("setNumProp: unknown propId %d", propId);
        break;
    }
}

static void ios_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length)
{
    UIView *view = get_node(nodeId);
    if (!view) return;
    if (![view isKindOfClass:[UIImageView class]]) return;

    NSData *nsdata = [NSData dataWithBytes:data length:(NSUInteger)length];
    UIImage *image = [UIImage imageWithData:nsdata];
    if (image) {
        ((UIImageView *)view).image = image;
    } else {
        LOGE("setImageData: failed to decode %d bytes (node=%d)", length, nodeId);
    }
    LOGI("setImageData(node=%d, %d bytes)", nodeId, length);
}

static void ios_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId)
{
    UIView *view = get_node(nodeId);
    if (!view) return;

    switch (eventType) {
    case UI_EVENT_CLICK:
        view.tag = callbackId;
        LOGI("setHandler(node=%d, click, callback=%d)", nodeId, callbackId);
        break;
    case UI_EVENT_TEXT_CHANGE:
        view.tag = callbackId;
        if ([view isKindOfClass:[UITextField class]]) {
            [(UITextField *)view addTarget:[IOSBridgeHandler shared]
                                    action:@selector(handleTextChange:)
                          forControlEvents:UIControlEventEditingChanged];
        }
        LOGI("setHandler(node=%d, textChange, callback=%d)", nodeId, callbackId);
        break;
    default:
        LOGI("setHandler: unknown eventType %d", eventType);
        break;
    }
}

static void ios_add_child(int32_t parentId, int32_t childId)
{
    UIView *parent = get_node(parentId);
    UIView *child  = get_node(childId);
    if (!parent || !child) return;

    /* For ScrollView nodes, children go into the content stack, not the scroll view itself */
    UIView *addTarget = nil;
#ifdef DYNAMIC_NODE_POOL
    if (parentId >= 0 && parentId < g_pool_capacity)
        addTarget = g_content_views[parentId];
#else
    if (parentId >= 0 && parentId < MAX_NODES)
        addTarget = g_content_views[parentId];
#endif
    if (!addTarget) addTarget = parent;
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
        /* Clear content_views in the same pass */
#ifdef DYNAMIC_NODE_POOL
        if (g_content_views && i < g_pool_capacity)
#endif
        g_content_views[i] = nil;
    }
    g_next_node_id = 1;
    /* Dynamic mode: keep allocations to avoid malloc/free churn each frame. */
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
    [IOSBridgeHandler shared].haskellCtx = haskellCtx;

#ifdef DYNAMIC_NODE_POOL
    if (!g_nodes) {
        g_pool_capacity = INITIAL_POOL_SIZE;
        g_nodes = (__strong UIView **)calloc((size_t)g_pool_capacity, sizeof(UIView *));
        g_content_views = (__strong UIView **)calloc((size_t)g_pool_capacity, sizeof(UIView *));
    } else {
        for (int i = 0; i < g_pool_capacity; i++) {
            g_nodes[i] = nil;
            g_content_views[i] = nil;
        }
    }
#else
    memset(g_nodes, 0, sizeof(g_nodes));
    memset(g_content_views, 0, sizeof(g_content_views));
#endif
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
