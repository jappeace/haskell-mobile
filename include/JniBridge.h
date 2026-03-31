/*
 * JniBridge.h — CPP macros for parameterised JNI symbol names.
 *
 * Consumers pass -DJNI_PACKAGE=me_jappie_myapp when compiling
 * jni_bridge.c (and any extra JNI C sources) so the resulting
 * symbols match the Java package of the actual application.
 *
 * Default: me_jappie_haskellmobile (haskell-mobile's own demo app).
 */

#ifndef JNI_BRIDGE_H
#define JNI_BRIDGE_H

#ifndef JNI_PACKAGE
#define JNI_PACKAGE me_jappie_haskellmobile
#endif

#ifndef JNI_CLASS
#define JNI_CLASS MainActivity
#endif

/* Two levels of indirection so JNI_PACKAGE / JNI_CLASS are expanded
   before token-pasting. */
#define JNI_METHOD_NAME3(pkg, cls, m) Java_ ## pkg ## _ ## cls ## _ ## m
#define JNI_METHOD_NAME2(pkg, cls, m) JNI_METHOD_NAME3(pkg, cls, m)
#define JNI_METHOD(m) JNI_METHOD_NAME2(JNI_PACKAGE, JNI_CLASS, m)

#endif /* JNI_BRIDGE_H */
