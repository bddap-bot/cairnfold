#!/usr/bin/env bash
# Plays the stress scene, demo/stress.json, and holds each phase to the frame budget in game/src/budget.gd:
#   bench.sh OUT_DIR                          desktop renderer: draw calls and primitives only, its GPU is no target
#   bench.sh OUT_DIR SSH_HOST BUNDLE.tar.gz   a Steam Frame, from a scratch install that leaves ~/cairnfold alone:
#                                             both eyes' pixels in one window, since the runtime renders nothing
#                                             unworn, so its GPU times compare builds but are not the headset's
#   bench.sh OUT_DIR --android APK            a Quest over adb (ANDROID_SERIAL picks it), in the headset proper, its
#                                             proximity sensor held closed so no one need wear it: the budget check
# On a Quest, exits 1 when a phase the build must hold goes over budget; phases named "sweep/..." only measure.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
device=desktop
if [ "${2:-}" = --android ]; then
  device=quest
  pkg=io.github.bddapbot.cairnfold
  dir=/sdcard/Android/data/$pkg/files/bench
  adb install -r "$3" > /dev/null
  adb shell "rm -rf $dir; mkdir -p $dir"
  adb push "$here/../demo/stress.json" "$dir/stress.json" > /dev/null
  adb shell am broadcast -a com.oculus.vrpowermanager.prox_close > /dev/null
  trap 'adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable > /dev/null' EXIT
  adb shell am force-stop "$pkg"
  adb logcat -c
  adb shell am start -W -n "$pkg/com.godot.game.GodotApp" --esa command_line_params "--,--script,$dir/stress.json,--metrics,$dir/metrics.json,--capture-dir,$dir" > /dev/null
  for _ in $(seq 900); do
    sleep 1
    adb shell pidof "$pkg" > /dev/null || break
  done
  adb logcat -d > "$out/logcat.txt"
  adb pull "$dir/." "$out/" > /dev/null
elif [ $# -ge 3 ]; then
  device=frame
  ssh "$2" 'set -e; rm -rf cairnfold-bench; mkdir cairnfold-bench; tar -xz -C cairnfold-bench; cd cairnfold-bench/cairnfold; mkdir log
    bin/godot --headless --path game --import > log/import.log 2>&1
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
    status=0; timeout 900 bin/godot --path game --resolution 3456x1728 --xr-mode off -- --desktop --script "$PWD/demo/stress.json" --metrics "$PWD/log/metrics.json" --capture-dir "$PWD/log" > log/godot.log 2>&1 || status=$?
    echo "bench: $(cat REVISION) exit $status"' < "$3"
  scp -q "$2:cairnfold-bench/cairnfold/log/*" "$out/"
else
  CAIRNFOLD_QUIT_AFTER=900 "$here/render.sh" "$here/../demo/stress.json" "$out" > "$out/godot.log" 2>&1
fi
python3 - "$out" "$device" <<'PY'
import json, os, re, sys
out, device = sys.argv[1], sys.argv[2]
d = json.load(open(os.path.join(out, "metrics.json")))
budget = d["info"]["budget"]
phases = {}
for s in d["seconds"]:
    if s["label"] != "-":
        phases.setdefault(s["label"], []).append(s)
# Per frame GPU milliseconds by phase: the Frame's driver time, or the Quest runtime's App= time per logcat second.
gpu = {}
if device == "frame":
    for name, secs in phases.items():
        gpu[name] = [s["gpu_ms"] / s["frames"] for s in secs[1:] if "gpu_ms" in s]
elif device == "quest":
    label = "-"
    for line in open(os.path.join(out, "logcat.txt"), errors="replace"):
        m = re.search(r'"op": "label", "name": "([^"]*)"', line)
        if m:
            label = m.group(1)
        m = re.search(r"VrApi.*FPS=(\d+)/\d+.*App=([\d.]+)ms", line)
        if m and label != "-":
            gpu.setdefault(label, []).append(float(m.group(2)))
    for v in gpu.values():
        v.pop(0)
print(f"{device}: budget {budget['gpu_ms']:.2f} ms of GPU time a frame at {budget['refresh_hz']:.0f} Hz, held on a Quest")
print(f"{'phase':18} {'frame p50':>9} {'p99':>7} {'draws':>6} {'prims':>9} {'gpu ms':>7}")
over = []
for name, secs in phases.items():
    secs = secs[1:] or secs
    mid = lambda xs: sorted(xs)[len(xs) // 2] if xs else float("nan")
    row = f"{name:18} {mid([s['p50'] for s in secs]):9.2f} {max(s['p99'] for s in secs):7.2f} {max(s['draws'] for s in secs):6} {max(s['prims'] for s in secs):9}"
    if gpu.get(name):
        g = mid(gpu[name])
        row += f" {g:7.2f}"
        if device == "quest":
            held = g <= budget["gpu_ms"]
            row += " holds" if held else " OVER"
            if not held and not name.startswith("sweep/"):
                over.append(name)
    print(row)
if over:
    print("over budget: " + ", ".join(over))
    sys.exit(1)
PY
