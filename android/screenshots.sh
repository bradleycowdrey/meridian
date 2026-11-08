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
# Keep a running log on the runner, so a crash (or the emulator going offline) still leaves a trace.
adb logcat -c; (adb logcat -v time > "$OUT/logcat-full.txt" 2>&1 &)
# Screens without city photos first, so if the emulator drops out we can see which screen took it down.
# The main list piece by piece first (CI diagnostics): off= parts left out of the cards.
for step in "rows,footer" "footer" "rows" "tiles,footer"; do
  timeout 180 adb wait-for-device || { echo "emulator gone before main off=$step" >> "$OUT/launch.txt"; break; }
  adb shell am force-stop com.bradcowdrey.meridian
  adb shell am start -n com.bradcowdrey.meridian/.MainActivity --ez screenshots true --es screen main --es off "$step" >> "$OUT/launch.txt" 2>&1
  sleep 9
  adb exec-out screencap -p > "$OUT/diag-main-off-${step//,/-}.png"
  echo "$(date +%T) shot main off=$step ($(stat -c %s "$OUT/diag-main-off-${step//,/-}.png") bytes)" >> "$OUT/launch.txt"
done
for screen in settings terms date find add widgets main travel edit; do
  timeout 180 adb wait-for-device || { echo "emulator gone before $screen" >> "$OUT/launch.txt"; break; }
  adb shell am force-stop com.bradcowdrey.meridian
  adb shell am start -n com.bradcowdrey.meridian/.MainActivity --ez screenshots true --es screen "$screen" >> "$OUT/launch.txt" 2>&1
  sleep 7
  adb exec-out screencap -p > "$OUT/screen-$screen.png"
  echo "$(date +%T) shot $screen" >> "$OUT/launch.txt"
done
adb shell dumpsys meminfo com.bradcowdrey.meridian > "$OUT/meminfo.txt" 2>&1
adb logcat -d | grep -i -E "meridian|AndroidRuntime|FATAL" | tail -300 > "$OUT/logcat.txt"
