#!/usr/bin/env bash
# Install the confetti animation reproducer on a Wear OS watch (armeabi-v7a / 32-bit ARM).
# Connect the watch via ADB (Wi-Fi or USB debugging) before running.

set -euo pipefail

adb uninstall me.jappie.hatter 2>/dev/null || true
adb install "$(nix-build nix/confetti-repro-apk.nix --argstr androidArch armv7a)/hatter-confetti-repro.apk"
