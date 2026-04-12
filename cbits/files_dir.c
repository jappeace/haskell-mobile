/*
 * App files directory path.
 *
 * Uses a set/get pattern: platform bridges call setAppFilesDir() during
 * initialization, and Haskell code reads it via getAppFilesDir().
 *
 * Android: jni_bridge.c calls setAppFilesDir() in JNI_OnLoad after
 *          querying Activity.getFilesDir().getAbsolutePath() via JNI.
 * iOS:     UIBridgeIOS.m calls setAppFilesDir() in setup_ios_ui_bridge
 *          after querying NSSearchPathForDirectoriesInDomains.
 * Desktop: falls back to "." (current working directory).
 */

#include <stdlib.h>

static const char *g_app_files_dir = NULL;

void setAppFilesDir(const char *path)
{
    g_app_files_dir = path;  /* caller owns the memory (static/strdup'd) */
}

const char* getAppFilesDir(void)
{
    if (g_app_files_dir) return g_app_files_dir;
    return ".";
}
