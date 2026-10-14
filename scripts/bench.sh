#!/usr/bin/env bash
# Plays the stress scene, demo/stress.json, and holds each phase to the frame budget in game/src/budget.gd:
#   bench.sh OUT_DIR                          desktop renderer: draw calls and primitives only, its GPU is no target
#   bench.sh OUT_DIR SSH_HOST BUNDLE.tar.gz   a Steam Frame, from a scratch install that leaves ~/cairnfold alone:
#                                             both eyes' pixels in one window, since the runtime renders nothing
#                                             unworn, so its GPU times compare builds but are not the headset's
#   bench.sh OUT_DIR --android APK            a Quest over adb (ANDROID_SERIAL picks it), in the headset proper, its
#                                             proximity sensor held closed so no one need wear it: the budget check
# On a Quest, exits 1 when a phase the build must hold goes over budget; phases named "sweep/..." only measure.
# CAIRNFOLD_PLAYERS=N adds N-1 headless players from this host, who join the measured instance and stand in view
# streaming their heads and hands.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
# Which ducks come to the stress scene's ponds: this one brings the most there can be, two families of five.
seed=25
device=desktop
players=${CAIRNFOLD_PLAYERS:-1}
case $players in [1-8]) ;; *) echo "bench: CAIRNFOLD_PLAYERS is 1 to 8" >&2; exit 1 ;; esac
# With other players the measured instance waits for them all before its first phase.
python3 - "$here/../demo/stress.json" "$players" > "$out/stress.json" <<'PY'
import json, sys
steps = json.load(open(sys.argv[1]))
players = int(sys.argv[2])
if players > 1:
    steps.insert(0, {"op": "until", "players": players, "seconds": 180})
print(json.dumps(steps))
PY
[ "$players" -eq 1 ] || godot4 --headless --path "$here/../game" --import > "$out/import.log" 2>&1
guests=()
measured=
stop() {
  local p
  for p in "${guests[@]}"; do kill "$p" 2>/dev/null || true; done
  [ -z "$measured" ] || kill -- "-$measured" 2>/dev/null || true
}
trap stop EXIT
# join LOG_CMD... -- ADDR: once the measured instance's log, as LOG_CMD prints it, names the port it hosts on, the
# other players join it at ADDR, each from its own spot looking towards the middle.
join() {
  local cmd=() addr port='' spots=("6 6" "10 2" "14 -2" "-6 8" "-10 4" "-12 -4" "2 12") g x z
  while [ "$1" != -- ]; do cmd+=("$1"); shift; done
  addr=$2
  [ -n "$addr" ] || { echo "bench: no address for the measured instance" >&2; exit 1; }
  for _ in $(seq 180); do
    port=$("${cmd[@]}" 2>/dev/null | sed -n 's/.*session: hosting on port \([0-9]*\).*/\1/p' | tail -1 || true)
    [ -n "$port" ] && break
    sleep 1
  done
  [ -n "$port" ] || { echo "bench: the measured instance never hosted" >&2; exit 1; }
  for ((g = 1; g < players; g++)); do
    read -r x z <<<"${spots[$((g - 1))]}"
    cat > "$out/guest$g.json" <<J
[{"op": "place", "x": $x, "z": $z}, {"op": "until", "players": $players, "seconds": 180}, {"op": "view", "eye": [$x, 1.65, $z], "at": [0, 1.4, 0], "ground": true}, {"op": "hands", "left": [-0.25, -0.35, -0.35], "right": [0.25, -0.3, -0.4]}, {"op": "wait", "seconds": 1200}]
J
    (cd "$out" && exec timeout 1500 godot4 --headless --path "$here/../game" --xr-mode off -- --desktop --join "$addr:$port" \
      --port 7536 --avatar "$g" --script "$out/guest$g.json") > "$out/guest$g.log" 2>&1 < /dev/null &
    guests+=($!)
  done
}
# same REVISION: the other players run this checkout, so the measured build must be its revision.
same() {
  local built=$1
  shift
  [ "$players" -eq 1 ] || { [ "$built" = "$(git -C "$here" rev-parse "${@:-HEAD}")" ] && git -C "$here" diff --quiet HEAD; } ||
    { echo "bench: the build is $built, this checkout $(git -C "$here" rev-parse HEAD); other players need one revision, committed" >&2; exit 1; }
}
if [ "${2:-}" = --android ]; then
  device=quest
  pkg=io.github.bddapbot.cairnfold
  dir=/sdcard/Android/data/$pkg/files/bench
  adb install -r "$3" > /dev/null
  same "$(adb shell dumpsys package "$pkg" | sed -n 's/.*versionName=//p' | head -1 | tr -d '\r')" --short HEAD
  adb shell "rm -rf $dir; mkdir -p $dir"
  adb push "$out/stress.json" "$dir/stress.json" > /dev/null
  adb shell am broadcast -a com.oculus.vrpowermanager.prox_close > /dev/null
  trap 'adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable > /dev/null || true; adb shell am force-stop "$pkg" || true; stop' EXIT
  adb shell am force-stop "$pkg"
  adb logcat -c
  adb shell am start -W -n "$pkg/com.godot.game.GodotApp" --esa command_line_params "--,--script,$dir/stress.json,--metrics,$dir/metrics.json,--capture-dir,$dir,--seed,$seed" > /dev/null
  if [ "$players" -gt 1 ]; then
    join adb logcat -d -- "$(adb shell ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1)"
  fi
  for _ in $(seq 900); do
    sleep 1
    adb shell pidof "$pkg" > /dev/null || break
  done
  adb logcat -d > "$out/logcat.txt"
  adb pull "$dir/." "$out/" > /dev/null
elif [ $# -ge 3 ]; then
  device=frame
  ssh "$2" 'set -e; rm -rf cairnfold-bench; mkdir cairnfold-bench; tar -xz -C cairnfold-bench; cd cairnfold-bench/cairnfold; mkdir log
    bin/godot --headless --path game --import > log/import.log 2>&1' < "$3"
  same "$(ssh -n "$2" cat cairnfold-bench/cairnfold/REVISION)"
  scp -q "$out/stress.json" "$2:cairnfold-bench/cairnfold/log/stress.json"
  ssh -n "$2" 'cd cairnfold-bench/cairnfold
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
    status=0; timeout 900 bin/godot --path game --resolution 3456x1728 --xr-mode off -- --desktop --script "$PWD/log/stress.json" --metrics "$PWD/log/metrics.json" --capture-dir "$PWD/log" --seed '"$seed"' > log/godot.log 2>&1 & echo $! > log/pid; wait $! || status=$?
    rm log/pid; echo "bench: $(cat REVISION) exit $status"' &
  remote=$!
  trap 'ssh -n "$2" "[ ! -f cairnfold-bench/cairnfold/log/pid ] || kill \$(cat cairnfold-bench/cairnfold/log/pid)" || true; stop' EXIT
  if [ "$players" -gt 1 ]; then
    join ssh -n "$2" cat cairnfold-bench/cairnfold/log/godot.log -- \
      "$(ssh -n "$2" "ip -4 route get 1.1.1.1" | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
  fi
  wait "$remote"
  scp -rq "$2:cairnfold-bench/cairnfold/log/*" "$out/"
else
  setsid env CAIRNFOLD_QUIT_AFTER=900 "$here/render.sh" "$out/stress.json" "$out" -- --seed "$seed" > "$out/godot.log" 2>&1 &
  measured=$!
  [ "$players" -eq 1 ] || join cat "$out/godot.log" -- 127.0.0.1
  wait "$measured"
  measured=
fi
if [ "$players" -gt 1 ] && grep -qs "driver: until .* timed out" "$out"/godot.log "$out"/logcat.txt "$out"/guest*.log; then
  echo "bench: not all $players players joined" >&2
  exit 1
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
