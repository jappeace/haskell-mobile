#!/usr/bin/env bash
# Install the EaseIn translate animation demo on an Android phone (aarch64).
# Connect the device via ADB before running.

set -euo pipefail

adb uninstall me.jappie.hatter 2>/dev/null || true
adb install "$(nix-build nix/ease-in-translate-apk.nix)/hatter-ease-in-translate.apk"
