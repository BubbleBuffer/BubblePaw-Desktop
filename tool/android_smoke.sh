#!/usr/bin/env bash
# Runs inside the Android emulator (CI): installs the x86_64 debug APK,
# launches it, and fails when the app crashes or is not running after a wait.
set -u
apk=build/app/outputs/flutter-apk/app-debug.apk
pkg=cc.breadcat.bubblepaw_desktop
adb logcat -c
adb install -r "$apk" || exit 1
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 || exit 1
for i in $(seq 1 12); do
  sleep 5
  if adb logcat -d | grep -q "FATAL EXCEPTION"; then
    adb logcat -d | grep -B2 -A25 "FATAL EXCEPTION" | head -80
    exit 1
  fi
done
if [ -z "$(adb shell pidof "$pkg")" ]; then
  echo "the app is not running after 60 s"
  adb logcat -d | tail -80
  exit 1
fi
# A native library that cannot load shows up as an UnsatisfiedLinkError.
if adb logcat -d | grep -q "UnsatisfiedLinkError"; then
  adb logcat -d | grep -B2 -A10 "UnsatisfiedLinkError" | head -40
  exit 1
fi
adb exec-out screencap -p > smoke.png
echo "the app started and stayed up"
