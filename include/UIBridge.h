#ifndef UI_BRIDGE_H
#define UI_BRIDGE_H

#include <stdint.h>

/* Node types */
#define UI_NODE_TEXT       0
#define UI_NODE_BUTTON     1
#define UI_NODE_COLUMN     2
#define UI_NODE_ROW        3
#define UI_NODE_TEXT_INPUT  4
#define UI_NODE_SCROLL_VIEW 5

/* Property IDs for string properties */
#define UI_PROP_TEXT      0
#define UI_PROP_COLOR     1
#define UI_PROP_HINT      2

/* Property IDs for numeric properties */
#define UI_PROP_FONT_SIZE 0
#define UI_PROP_PADDING   1

/* Event types */
#define UI_EVENT_CLICK       0
#define UI_EVENT_TEXT_CHANGE  1

/*
 * Function pointer table filled by the platform (Android/iOS).
 * Haskell calls through these pointers via ui_* wrappers.
 * When NULL (desktop), stubs log to stderr and return dummy IDs.
 */
typedef struct UIBridgeCallbacks {
    int32_t (*createNode)(int32_t nodeType);
    void    (*setStrProp)(int32_t nodeId, int32_t propId, const char *value);
    void    (*setNumProp)(int32_t nodeId, int32_t propId, double value);
    void    (*setHandler)(int32_t nodeId, int32_t eventType, int32_t callbackId);
    void    (*addChild)(int32_t parentId, int32_t childId);
    void    (*removeChild)(int32_t parentId, int32_t childId);
    void    (*destroyNode)(int32_t nodeId);
    void    (*setRoot)(int32_t nodeId);
    void    (*clear)(void);
} UIBridgeCallbacks;

/* Register platform callbacks. Ownership is NOT transferred. */
void ui_register_callbacks(UIBridgeCallbacks *callbacks);

/* Platform-agnostic wrappers (delegate to callbacks or desktop stubs) */
int32_t ui_create_node(int32_t nodeType);
void    ui_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
void    ui_set_num_prop(int32_t nodeId, int32_t propId, double value);
void    ui_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
void    ui_add_child(int32_t parentId, int32_t childId);
void    ui_remove_child(int32_t parentId, int32_t childId);
void    ui_destroy_node(int32_t nodeId);
void    ui_set_root(int32_t nodeId);
void    ui_clear(void);

#endif /* UI_BRIDGE_H */
