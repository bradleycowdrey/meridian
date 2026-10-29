#!/usr/bin/env bash
# CI: installs the debug app on the emulator and takes a screenshot of every screen.
OUT="$1"; mkdir -p "$OUT"
APK=android/app/build/outputs/apk/debug/app-debug.apk
adb install -r "$APK" > "$OUT/install.txt" 2>&1
# A tidy status bar: 9:41, full battery and signal.
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
for screen in main travel add edit settings widgets terms; do
  adb shell am force-stop com.bradcowdrey.meridian
  adb shell am start -n com.bradcowdrey.meridian/.MainActivity --ez screenshots true --es screen "$screen" >> "$OUT/launch.txt" 2>&1
  sleep 7
  adb exec-out screencap -p > "$OUT/screen-$screen.png"
done
adb logcat -d | grep -i -E "meridian|AndroidRuntime|FATAL" | tail -300 > "$OUT/logcat.txt"
