#ifndef DIALOG_BRIDGE_H
#define DIALOG_BRIDGE_H

#include <stdint.h>

/* Dialog action codes (must match Hatter.Dialog) */
#define DIALOG_BUTTON_1   0
#define DIALOG_BUTTON_2   1
#define DIALOG_BUTTON_3   2
#define DIALOG_DISMISSED  3

/*
 * Platform-agnostic dialog bridge.
 *
 * Haskell calls dialog_show() through this wrapper.
 * When no platform callback is registered (desktop), a stub logs to stderr
 * and auto-presses button 1 via haskellOnDialogResult.
 *
 * On Android/iOS the platform-specific setup function fills in a real
 * implementation via dialog_register_impl().
 */

/* Show a modal dialog with up to 3 buttons.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * title:     null-terminated dialog title.
 * message:   null-terminated dialog message.
 * button1:   null-terminated label for button 1 (required).
 * button2:   null-terminated label for button 2, or NULL to omit.
 * button3:   null-terminated label for button 3, or NULL to omit. */
void dialog_show(void *ctx, int32_t requestId, const char *title,
                 const char *message, const char *button1,
                 const char *button2, const char *button3);

/* Register the platform-specific implementation.
 * Called by platform setup functions (setup_android_dialog_bridge, etc). */
void dialog_register_impl(
    void (*show_impl)(void *, int32_t, const char *, const char *,
                      const char *, const char *, const char *));

#endif /* DIALOG_BRIDGE_H */
