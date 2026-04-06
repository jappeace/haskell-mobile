/*
 * Platform-specific locale detection.
 *
 * Uses a set/get pattern: platform bridges call setSystemLocale() during
 * initialization, and Haskell code reads it via getSystemLocale().
 *
 * Android: jni_bridge.c calls setSystemLocale() in JNI_OnLoad after
 *          querying Locale.getDefault().toLanguageTag() via JNI.
 * iOS:     UIBridgeIOS.m calls setSystemLocale() in setup_ios_ui_bridge
 *          after querying NSLocale.currentLocale.
 * Desktop: falls back to LANG environment variable, then "en".
 */

#include <stdlib.h>

static const char *g_system_locale = NULL;

void setSystemLocale(const char *locale)
{
    g_system_locale = locale;  /* caller owns the memory (static/strdup'd) */
}

const char* getSystemLocale(void)
{
    if (g_system_locale) return g_system_locale;
#ifndef __ANDROID__
    {
        const char *lang = getenv("LANG");
        if (lang) return lang;
    }
#endif
    return "en";
}
