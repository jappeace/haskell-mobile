/*
 * Platform-agnostic UI bridge dispatcher.
 *
 * Stores a pointer to UIBridgeCallbacks (filled by Android/iOS).
 * Each ui_* function delegates to the corresponding function pointer.
 * When no callbacks are registered (desktop), functions log to stderr
 * and return dummy IDs so that cabal build/test works without native UI.
 */

#include "UIBridge.h"
#include <stdio.h>

static UIBridgeCallbacks *g_callbacks = NULL;
static int32_t g_stub_next_id = 1;

/* Stub free stack for ID reclamation (mirrors real platform behaviour) */
#define STUB_MAX_NODES 256
static int32_t g_stub_free_stack[STUB_MAX_NODES];
static int32_t g_stub_free_count = 0;

void ui_register_callbacks(UIBridgeCallbacks *callbacks)
{
    g_callbacks = callbacks;
}

int32_t ui_create_node(int32_t nodeType)
{
    if (g_callbacks && g_callbacks->createNode) {
        return g_callbacks->createNode(nodeType);
    }
    int32_t id;
    if (g_stub_free_count > 0) {
        id = g_stub_free_stack[--g_stub_free_count];
    } else {
        id = g_stub_next_id++;
    }
    fprintf(stderr, "[UIBridge stub] createNode(type=%d) -> %d\n", nodeType, id);
    return id;
}

void ui_set_str_prop(int32_t nodeId, int32_t propId, const char *value)
{
    if (g_callbacks && g_callbacks->setStrProp) {
        g_callbacks->setStrProp(nodeId, propId, value);
        return;
    }
    fprintf(stderr, "[UIBridge stub] setStrProp(node=%d, prop=%d, value=\"%s\")\n",
            nodeId, propId, value ? value : "(null)");
}

void ui_set_num_prop(int32_t nodeId, int32_t propId, double value)
{
    if (g_callbacks && g_callbacks->setNumProp) {
        g_callbacks->setNumProp(nodeId, propId, value);
        return;
    }
    fprintf(stderr, "[UIBridge stub] setNumProp(node=%d, prop=%d, value=%.2f)\n",
            nodeId, propId, value);
}

void ui_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length)
{
    if (g_callbacks && g_callbacks->setImageData) {
        g_callbacks->setImageData(nodeId, data, length);
        return;
    }
    fprintf(stderr, "[UIBridge stub] setImageData(node=%d, %d bytes)\n", nodeId, length);
}

void ui_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId)
{
    if (g_callbacks && g_callbacks->setHandler) {
        g_callbacks->setHandler(nodeId, eventType, callbackId);
        return;
    }
    fprintf(stderr, "[UIBridge stub] setHandler(node=%d, event=%d, callback=%d)\n",
            nodeId, eventType, callbackId);
}

void ui_add_child(int32_t parentId, int32_t childId)
{
    if (g_callbacks && g_callbacks->addChild) {
        g_callbacks->addChild(parentId, childId);
        return;
    }
    fprintf(stderr, "[UIBridge stub] addChild(parent=%d, child=%d)\n",
            parentId, childId);
}

void ui_remove_child(int32_t parentId, int32_t childId)
{
    if (g_callbacks && g_callbacks->removeChild) {
        g_callbacks->removeChild(parentId, childId);
        return;
    }
    fprintf(stderr, "[UIBridge stub] removeChild(parent=%d, child=%d)\n",
            parentId, childId);
}

void ui_destroy_node(int32_t nodeId)
{
    if (g_callbacks && g_callbacks->destroyNode) {
        g_callbacks->destroyNode(nodeId);
        return;
    }
    fprintf(stderr, "[UIBridge stub] destroyNode(node=%d)\n", nodeId);
    if (g_stub_free_count < STUB_MAX_NODES) {
        g_stub_free_stack[g_stub_free_count++] = nodeId;
    }
}

void ui_set_root(int32_t nodeId)
{
    if (g_callbacks && g_callbacks->setRoot) {
        g_callbacks->setRoot(nodeId);
        return;
    }
    fprintf(stderr, "[UIBridge stub] setRoot(node=%d)\n", nodeId);
}

void ui_clear(void)
{
    if (g_callbacks && g_callbacks->clear) {
        g_callbacks->clear();
        return;
    }
    g_stub_next_id = 1;
    g_stub_free_count = 0;
    fprintf(stderr, "[UIBridge stub] clear()\n");
}
