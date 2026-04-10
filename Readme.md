[![CI](https://img.shields.io/github/actions/workflow/status/jappeace/haskell-mobile/ci.yaml?branch=master)](https://github.com/jappeace/haskell-mobile/actions)

>  Why is a raven like a writing-desk?

![hatter](./hatter.png)

# Hatter
It's like flutter but instead of dart, haskell!

Write native mobile apps in Haskell.
This works similar to react native where we have
thight bindings on the existing UI frameworks
provided android and IOS.

This project cross-compiles a Haskell library to Android (APK) and iOS (static library / IPA),
with a thin platform-native UI layer (Kotlin for Android, Swift for iOS).
The library fully controls the UI.
This is different from say Simplex chat where they appear to use 
