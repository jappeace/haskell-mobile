/*
 * dummy_jni_consumer.c — trivial extra JNI file that exercises the
 * extraJniBridge linker path in mkAndroidLib.
 *
 * Real consumer apps (e.g. prrrrrrrrr) provide extra JNI methods for
 * storage, sensors, etc.  This stub mirrors that pattern with a no-op
 * method so the consumer simulation test covers the same build path.
 */

#include <jni.h>
#include "JniBridge.h"

/* No-op consumer JNI method — exercises extraJniBridge linker path. */
JNIEXPORT jint JNICALL
JNI_METHOD(dummyConsumerMethod)(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    return 42;
}
