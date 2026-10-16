#!/usr/bin/env bash
# Plays the stress scene, demo/stress.json, and holds each phase to the frame budget in game/src/budget.gd:
#   bench.sh OUT_DIR                          desktop renderer: draw calls and primitives only, its GPU is no target
#   bench.sh OUT_DIR SSH_HOST BUNDLE.tar.gz   a Steam Frame, from a scratch install of the linux-arm64 package that leaves ~/nestcombe alone,
#                                             in the headset's XR session unworn: SteamVR pauses the game while the
#                                             headset is in standby, so the run turns power.pauseCompositorOnStandby
#                                             off and restarts SteamVR, and puts both back on exit. Nothing else may
#                                             use SteamVR meanwhile. The GPU times are the headset's own render path;
#                                             a worn session's eye tracking and passthrough cameras are not in them
#   bench.sh OUT_DIR --android APK            a Quest over adb (ANDROID_SERIAL picks it), in the headset proper, its
#                                             proximity sensor held closed so no one need wear it: the budget check
# On a Quest, exits 1 when a phase the build must hold goes over budget; phases named "sweep/..." only measure.
# NESTCOMBE_SCENE=SCRIPT.json plays another demo script in place of the stress scene. The late column counts a phase's
# frames over 1.5x the refresh period from its first second, where its edits land; the others leave that second out.
# NESTCOMBE_PLAYERS=N adds N-1 headless players from this host, who join the measured instance and stand in view
# streaming their heads and hands.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
# Which ducks come to the stress scene's ponds: this one brings the most there can be, two families of five.
seed=25
device=desktop
players=${NESTCOMBE_PLAYERS:-1}
case $players in [1-8]) ;; *) echo "bench: NESTCOMBE_PLAYERS is 1 to 8" >&2; exit 1 ;; esac
# With other players the measured instance waits for them all before its first phase.
python3 - "${NESTCOMBE_SCENE:-$here/../demo/stress.json}" "$players" > "$out/stress.json" <<'PY'
import json, sys
steps = json.load(open(sys.argv[1]))
players = int(sys.argv[2])
if players > 1:
    first = next(i for i, step in enumerate(steps) if step.get("op") == "label")
    steps.insert(first + 1, {"op": "until", "players": players, "seconds": 180})
print(json.dumps(steps))
PY
[ "$players" -eq 1 ] || godot4 --headless --path "$here/../game" --import > "$out/import.log" 2>&1 ||
  { echo "bench: the other players' game did not import, see $out/import.log" >&2; exit 1; }
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
  pkg=io.github.bddapbot.nestcombe
  dir=/sdcard/Android/data/$pkg/files/bench
  serial=${ANDROID_SERIAL:-}
  case $serial in *:*) adb connect "$serial" > /dev/null ;; esac
  # shows SERVICE PATTERN [TEXT]: whether the first line of `dumpsys SERVICE` matching PATTERN holds TEXT. The
  # dump is read whole, since a grep stopping early would fail the pipe under pipefail.
  shows() {
    local dump
    dump=$(adb shell dumpsys "$1")
    grep -m1 "$2" <<< "$dump" | grep -q "${3:-}"
  }
  if ! failed=$(adb install -r -g "$3" 2>&1); then
    case $failed in
      *INSTALL_FAILED_UPDATE_INCOMPATIBLE* | *INSTALL_FAILED_VERSION_DOWNGRADE*)
        adb uninstall "$pkg" > /dev/null
        adb install -g "$3" > /dev/null ;;
      *) echo "$failed" >&2; exit 1 ;;
    esac
  fi
  same "$(adb shell dumpsys package "$pkg" | sed -n 's/.*versionName=//p' | head -1 | tr -d '\r')" --short HEAD
  adb shell "rm -rf $dir; mkdir -p $dir"
  adb push "$out/stress.json" "$dir/stress.json" > /dev/null
  # Off the head the headset loses tracking, and its Guardian then puts up a dialog the shell keeps drawing beside
  # the game, at the cost of the game's GPU time, so the Guardian is held paused. The clocks are held at level 4,
  # the highest the headset sustains warm, so runs compare: left free it moves the GPU between 525 and 587 MHz as
  # it warms.
  saved_props=$(for k in guardian_pause cpuLevel gpuLevel; do printf '%s=%s ' "$k" "$(adb shell getprop "debug.oculus.$k" | tr -d '\r')"; done)
  logcat_pid=
  restore_headset() {
    local kv
    set +e
    [ -z "$logcat_pid" ] || kill "$logcat_pid" 2> /dev/null
    adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable > /dev/null
    for kv in $saved_props; do adb shell "setprop debug.oculus.${kv%%=*} '${kv#*=}'"; done
    adb shell am force-stop "$pkg"
    stop
  }
  trap restore_headset EXIT
  adb shell setprop debug.oculus.guardian_pause 1
  adb shell setprop debug.oculus.cpuLevel 4
  adb shell setprop debug.oculus.gpuLevel 4
  adb shell am broadcast -a com.oculus.vrpowermanager.prox_close > /dev/null
  for _ in $(seq 30); do
    shows vrpowermanager 'State: HEADSET_MOUNTED' && break
    sleep 1
  done
  shows vrpowermanager 'State: HEADSET_MOUNTED' || { echo "bench: the headset did not wake" >&2; exit 1; }
  # Streams logcat to the file, from where it left off after a drop: the headset's ring holds a minute or two.
  follow() {
    [ -z "$logcat_pid" ] || kill "$logcat_pid" 2> /dev/null || true
    local since
    since=$(grep -aE '^[0-9]{2}-[0-9]{2} [0-9:.]{12} ' "$out/logcat.txt" | tail -1 | cut -c1-18 || true)
    if [ -n "$since" ]; then
      adb logcat -T "$since" >> "$out/logcat.txt" &
    else
      adb logcat > "$out/logcat.txt" &
    fi
    logcat_pid=$!
  }
  # A Store or Library panel left open keeps the shell rendering beside the game and takes GPU time from it, which
  # no reading of the game's own App= time can subtract. A launch into a waking headset can also meet the shell's
  # controller check, with the controllers idle, or be paused as it starts, which crashes Godot. A fresh shell, with
  # the panels closed, starts with neither.
  fresh_shell() {
    local app
    for app in com.oculus.store com.oculus.panelapp.library com.oculus.vrshell; do adb shell am force-stop "$app"; done
    sleep 10
  }
  fresh_shell
  for try in 1 2 3; do
    adb shell am force-stop "$pkg"
    [ -z "$logcat_pid" ] || kill "$logcat_pid" 2> /dev/null || true
    logcat_pid=
    adb logcat -c
    : > "$out/logcat.txt"
    follow
    adb shell am start -n "$pkg/com.godot.game.GodotApp" --esa command_line_params "--,--script,$dir/stress.json,--metrics,$dir/metrics.json,--capture-dir,$dir,--seed,$seed" > /dev/null
    sleep 15
    shows "activity activities" topResumedActivity "$pkg" && break
    [ "$try" -lt 3 ] || { echo "bench: the game would not start; see $out/logcat.txt" >&2; exit 1; }
    echo "bench: launch $try did not hold, restarting the shell" >&2
    fresh_shell
  done
  if [ "$players" -gt 1 ]; then
    join cat "$out/logcat.txt" -- "$(adb shell ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1)"
  fi
  # The host's adb server can drop the headset mid-run: reconnect and follow the log again.
  for _ in $(seq 900); do
    sleep 1
    if ! adb get-state > /dev/null 2>&1; then
      case $serial in *:*) adb connect "$serial" > /dev/null 2>&1 || true ;; esac
      continue
    fi
    kill -0 "$logcat_pid" 2> /dev/null || follow
    adb shell pidof "$pkg" > /dev/null || ! adb get-state > /dev/null 2>&1 || break
  done
  kill "$logcat_pid" 2> /dev/null || true
  logcat_pid=
  adb pull "$dir/." "$out/" > /dev/null
elif [ $# -ge 3 ]; then
  device=frame
  ssh "$2" 'set -e; rm -rf nestcombe-bench; mkdir nestcombe-bench; tar -xz -C nestcombe-bench; mkdir nestcombe-bench/nestcombe/log' < "$3"
  same "$(ssh -n "$2" cat nestcombe-bench/nestcombe/REVISION)"
  scp -q "$out/stress.json" "$2:nestcombe-bench/nestcombe/log/stress.json"
  # standby HOST off|on: SteamVR reads its settings only as it starts.
  standby() {
    ssh -n "$1" 'cfg=$HOME/.config/openvr/config/steamvr.vrsettings saved=$cfg.bench
      export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
      if [ "'"$2"'" = off ]; then
        [ -f "$saved" ] || cp "$cfg" "$saved"
        python3 -c "import json, sys; s = json.load(open(sys.argv[1])); s.setdefault(\"power\", {})[\"pauseCompositorOnStandby\"] = False; json.dump(s, open(sys.argv[1], \"w\"), indent=3)" "$cfg"
      elif [ -f "$saved" ]; then
        mv "$saved" "$cfg"
      else
        exit 0
      fi
      systemctl --user restart steamvr
      for _ in $(seq 60); do pgrep -x vrcompositor > /dev/null && exit 0; sleep 1; done
      echo "bench: SteamVR did not come back" >&2; exit 1'
  }
  trap 'ssh -n "$2" "[ ! -f nestcombe-bench/nestcombe/log/pid ] || kill \$(cat nestcombe-bench/nestcombe/log/pid)" || true; standby "$2" on || true; stop' EXIT
  standby "$2" off
  ssh -n "$2" 'cd nestcombe-bench/nestcombe
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
    status=0; timeout 900 ./nestcombe -- --script "$PWD/log/stress.json" --metrics "$PWD/log/metrics.json" --capture-dir "$PWD/log" --seed '"$seed"' > log/godot.log 2>&1 & echo $! > log/pid; wait $! || status=$?
    rm log/pid; echo "bench: $(cat REVISION) exit $status"' &
  remote=$!
  if [ "$players" -gt 1 ]; then
    join ssh -n "$2" cat nestcombe-bench/nestcombe/log/godot.log -- \
      "$(ssh -n "$2" "ip -4 route get 1.1.1.1" | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
  fi
  wait "$remote"
  scp -rq "$2:nestcombe-bench/nestcombe/log/*" "$out/"
  standby "$2" on
else
  setsid env NESTCOMBE_QUIT_AFTER=900 "$here/render.sh" "$out/stress.json" "$out" -- --seed "$seed" > "$out/godot.log" 2>&1 &
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
for name in ["logcat.txt", "godot.log"]:
    path = os.path.join(out, name)
    if os.path.exists(path):
        with open(path, errors="replace") as log:
            if any("When supplying a custom region, it must be contained within the framebuffer rectangle" in line for line in log):
                sys.exit(f"bench: invalid framebuffer region; rendering failed, see {name}")
d = json.load(open(os.path.join(out, "metrics.json")))
budget = d["info"]["budget"]
phases = {}
for s in d["seconds"]:
    if s["label"] != "-":
        phases.setdefault(s["label"], []).append(s)
if not phases:
    sys.exit("bench: the run measured no phase; see the game's log")
if device == "frame" and not d["info"].get("xr"):
    sys.exit("bench: the game ran without an XR session; see the game's log")
# Per frame GPU milliseconds by phase: the Frame's driver time, or the Quest runtime's App= time per logcat second.
gpu = {}
if device == "frame":
    for name, secs in phases.items():
        gpu[name] = [s["gpu_ms"] / s["frames"] for s in secs[1:] if "gpu_ms" in s]
elif device == "quest":
    # Only the game's process counts, the one printing the labels. Another process rendering during a phase, as the
    # shell does under an open panel, shares the GPU with the game, so that phase's times are not the game's.
    label, game_pid = "-", None
    shared = {}
    for line in open(os.path.join(out, "logcat.txt"), errors="replace"):
        fields = line.split()
        pid = fields[2] if len(fields) > 2 else None
        m = re.search(r'"op": "label", "name": "([^"]*)"', line)
        if m:
            label, game_pid = m.group(1), pid
        m = re.search(r"VrApi.*FPS=(\d+)/\d+.*App=([\d.]+)ms", line)
        if m and label != "-" and pid == game_pid:
            gpu.setdefault(label, []).append(float(m.group(2)))
        elif m and label != "-":
            shared.setdefault(label, set()).add(pid)
    if shared:
        sys.exit("bench: another process rendered during " + ", ".join(f"{k} (pid {', '.join(sorted(v))})" for k, v in shared.items()) + "; see logcat.txt")
    for v in gpu.values():
        v.pop(0)
    unmeasured = [name for name in phases if not gpu.get(name) and not name.startswith("sweep/")]
    if unmeasured:
        sys.exit("bench: no runtime GPU time for " + ", ".join(unmeasured) + "; see logcat.txt")
print(f"{device}: budget {budget['gpu_ms']:.2f} ms of GPU time a frame at {budget['refresh_hz']:.0f} Hz, held on a Quest")
print(f"{'phase':18} {'frame p50':>9} {'p99':>7} {'late':>5} {'draws':>6} {'prims':>9} {'gpu ms':>7}")
over = []
for name, secs in phases.items():
    late = sum(s["late"] for s in secs)
    secs = secs[1:] or secs
    mid = lambda xs: sorted(xs)[len(xs) // 2] if xs else float("nan")
    row = f"{name:18} {mid([s['p50'] for s in secs]):9.2f} {max(s['p99'] for s in secs):7.2f} {late:5} {max(s['draws'] for s in secs):6} {max(s['prims'] for s in secs):9}"
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
