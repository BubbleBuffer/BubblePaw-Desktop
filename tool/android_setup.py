#!/usr/bin/env python3
"""Generates android/ for the phone build and patches it.

The Android project is not committed: CI (and anyone building the phone app)
runs `flutter create --platforms=android` and then this script. It sets the
app name, the permissions (internet, camera for the pairing QR code), the
minimum SDK and the one ABI the app ships: arm64-v8a, or $ANDROID_ABI (the
x86_64 emulator smoke test in CI).
"""
import os
import pathlib
import re
import sys

abi = os.environ.get("ANDROID_ABI", "arm64-v8a")
root = pathlib.Path(__file__).resolve().parent.parent
android = root / "android"
manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
if not manifest.exists():
    sys.exit("android/ is missing: run `flutter create --platforms=android .` first")

text = manifest.read_text(encoding="utf-8")
perms = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.CAMERA"/>\n'
    '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
)
if "android.permission.INTERNET" not in text:
    text = re.sub(r"(<manifest[^>]*>\n)", lambda m: m.group(1) + perms, text, count=1)
text = re.sub(r'android:label="[^"]*"', 'android:label="BubblePaw"', text, count=1)
manifest.write_text(text, encoding="utf-8")

for name in ("build.gradle.kts", "build.gradle"):
    gradle = android / "app" / name
    if not gradle.exists():
        continue
    g = gradle.read_text(encoding="utf-8")
    g = g.replace("flutter.minSdkVersion", "26")
    if "abiFilters" not in g:
        if name.endswith(".kts"):
            line = '        ndk { abiFilters += listOf("%s") }\n' % abi
        else:
            line = "        ndk { abiFilters '%s' }\n" % abi
        g = re.sub(
            r"(defaultConfig \{\n)",
            lambda m: m.group(1) + line,
            g,
            count=1,
        )
    gradle.write_text(g, encoding="utf-8")
print("android/ patched")
