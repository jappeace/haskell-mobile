# Consumer link test: build the Android library with a minimal consumer entry
# point that does not export any test-only symbols.
#
# Fails with "undefined reference to haskellFoo" if jni_bridge.c calls a
# haskell* function that is only exported from App.hs (consumer-replaceable).
{ sources ? import ../npins }:
import ./android.nix { inherit sources; mainModule = ../test/ScrollDemoMain.hs; }
