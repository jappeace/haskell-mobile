#ifndef BOTTOM_SHEET_BRIDGE_H
#define BOTTOM_SHEET_BRIDGE_H

#include <stdint.h>

/* Bottom sheet action codes (must match Hatter.BottomSheet) */
#define BOTTOM_SHEET_DISMISSED -1
/* actionCode >= 0: 0-based index of the selected item */

/*
 * Platform-agnostic bottom sheet bridge.
 *
 * Haskell calls bottom_sheet_show() through this wrapper.
 * When no platform callback is registered (desktop), a stub logs to stderr
 * and auto-selects the first item via haskellOnBottomSheetResult.
 *
 * On Android/iOS the platform-specific setup function fills in a real
 * implementation via bottom_sheet_register_impl().
 */

/* Show a bottom sheet with a title and newline-separated item labels.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * title:     null-terminated sheet title.
 * items:     null-terminated newline-separated item labels ("Edit\nDelete\nShare"). */
void bottom_sheet_show(void *ctx, int32_t requestId,
                       const char *title, const char *items);

/* Register the platform-specific implementation.
 * Called by platform setup functions (setup_android_bottom_sheet_bridge, etc). */
void bottom_sheet_register_impl(
    void (*show_impl)(void *, int32_t, const char *, const char *));

#endif /* BOTTOM_SHEET_BRIDGE_H */
