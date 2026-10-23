#!/usr/bin/env bash
# Plays the stress scene, demo/stress.json, and holds each phase to the frame budget in game/src/budget.gd:
#   bench.sh OUT_DIR                          desktop renderer: draw calls and primitives only, its GPU is no target
#   bench.sh OUT_DIR SSH_HOST BUNDLE.tar.gz UNWORN...
#                                             a Steam Frame, from a scratch install of the linux-arm64 package that leaves ~/nestcombe alone,
#                                             in the headset's XR session unworn. SteamVR pauses the game while the
#                                             headset is in standby, so the game runs as the command UNWORN... is
#                                             given as its last argument: a host command that runs that bash command
#                                             on the headset with power.pauseCompositorOnStandby off, restores the
#                                             setting after, even if its caller dies, and exits with the command's
#                                             status. Nothing else may use SteamVR meanwhile. The run autosaves every
#                                             edit to log/garden.save, as play does, so the late column counts each
#                                             save's frame. The GPU times are the headset's own render path; a worn
#                                             session's eye tracking and passthrough cameras are not in them
#   bench.sh OUT_DIR --android APK            the one Quest adb reaches, in the headset proper, its
#                                             proximity sensor held closed so no one need wear it: the budget check
# On a Quest, exits 1 when a phase the build must hold goes over budget; phases named "sweep/..." only measure.
# On a Frame, exits 1 when the game exits non-zero, a crash at quit included; the desktop run stops with its status.
# Each run's phases are recorded in perf/RIG/SCENE/, RIG the headset's model; commit the record with the change it
# measured. scripts/trend.py then compares it with the runs before, and a phase's GPU time rising fails the bench.
# NESTCOMBE_SCENE=SCRIPT.json plays another demo script in place of the stress scene. The late column counts a phase's
# frames over 1.5x the refresh period from its first second, where its edits land; the others leave that second out.
# The land max and land late columns are the longest frame and the late frames over the phase's landings: each window of
# game/src/metrics.gd's LANDING_S from a move of the play space's origin, a teleport or view; "-" for none.
# NESTCOMBE_ARGS="--quality 8" passes more game arguments on a Quest, each word its own.
# NESTCOMBE_PLAYERS=N adds N-1 headless players from this host, who join the measured instance and stand in view
# streaming their heads and hands. NESTCOMBE_WAVE=1 makes them flat-screen players repeatedly waving. NESTCOMBE_GUEST_AVATAR=FILE.vrm has each of them wear that VRM in place of a
# built-in avatar, to measure what a player's own avatar costs the others; on a Quest it is also pushed as bench/guest.vrm,
# which a scene's "figures" step stands in view with no other player or network (demo/avatar-cost.json).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
# Which ducks come to the stress scene's ponds: this one brings the most there can be, two families of five.
seed=25
device=desktop
game=0
rig=desktop
build=$(git -C "$here" rev-parse HEAD)
players=${NESTCOMBE_PLAYERS:-1}
read -ra extra <<< "${NESTCOMBE_ARGS:-}"
case $players in [1-8]) ;; *) echo "bench: NESTCOMBE_PLAYERS is 1 to 8" >&2; exit 1 ;; esac
# A scripted run hosts only when given a port.
hosting=
[ "$players" -eq 1 ] || hosting=7480
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
# The game is stopped this long after it starts: twice the scene's own seconds, so no scene outgrows it.
limit=$(python3 -c 'import json, sys; print(300 + 2 * round(sum(s.get("seconds", 0) for s in json.load(open(sys.argv[1])))))' "$out/stress.json")
[ "$players" -eq 1 ] || godot4 --headless --path "$here/../game" --import > "$out/import.log" 2>&1 ||
  { echo "bench: the other players' game did not import, see $out/import.log" >&2; exit 1; }
guest_avatar=()
if [ -n "${NESTCOMBE_GUEST_AVATAR:-}" ]; then
  mkdir -p "$out/avatars"
  cp "$NESTCOMBE_GUEST_AVATAR" "$out/avatars/"
  guest_avatar=(--avatars "$out/avatars")
fi
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
    python3 - "$x" "$z" "$players" "${NESTCOMBE_WAVE:-0}" > "$out/guest$g.json" <<'PYTHON'
import json, sys
x, z, players, wave = map(int, sys.argv[1:])
steps = [{"op": "place", "x": x, "z": z}, {"op": "until", "players": players, "seconds": 180}]
if wave:
    steps += [{"op": "face", "at": [0, 1.4, 0]}]
    steps += [{"op": "flat", "action": "wave", "seconds": 3}] * 400
else:
    steps += [{"op": "view", "eye": [x, 1.65, z], "at": [0, 1.4, 0], "ground": True},
              {"op": "hands", "left": [-0.25, -0.35, -0.35], "right": [0.25, -0.3, -0.4]},
              {"op": "wait", "seconds": 1200}]
print(json.dumps(steps))
PYTHON
    local flat=()
    [ "${NESTCOMBE_WAVE:-0}" != 1 ] || flat=(--flat)
    (cd "$out" && exec timeout 1500 godot4 --headless --path "$here/../game" --xr-mode off -- --desktop "${flat[@]}" --join "$addr:$port" \
      --port 7536 --avatar "$g" "${guest_avatar[@]}" --script "$out/guest$g.json") > "$out/guest$g.log" 2>&1 < /dev/null &
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
  pkg=$("$here/quest-install.sh" --package "$3")
  # The game makes its own output dir: on a Quest 3 it cannot write into one the shell made.
  files=/sdcard/Android/data/$pkg/files
  dir=$files/bench
  # A host-side logcat over wireless adb stalls with no sign, so the headset records its own.
  log=/data/local/tmp/nestcombe-bench.log
  # shows SERVICE PATTERN [TEXT]: whether the first line of `dumpsys SERVICE` matching PATTERN holds TEXT. The
  # dump is read whole, since a grep stopping early would fail the pipe under pipefail.
  shows() {
    local dump
    dump=$(adb shell dumpsys "$1")
    grep -m1 "$2" <<< "$dump" | grep -q "${3:-}"
  }
  rig=$(adb shell getprop ro.product.model | tr -d '\r' | tr 'A-Z ' 'a-z-')
  "$here/quest-install.sh" "$3"
  build=$(adb shell dumpsys package "$pkg" | sed -n 's/.*versionName=//p' | head -1 | tr -d '\r')
  same "$build" --short HEAD
  adb shell "rm -rf $dir"
  adb push "$out/stress.json" "$files/bench.json" > /dev/null
  [ -z "${NESTCOMBE_GUEST_AVATAR:-}" ] || adb push "$NESTCOMBE_GUEST_AVATAR" "$dir/guest.vrm" > /dev/null
  # Off the head the headset loses tracking, and its Guardian then puts up a dialog the shell keeps drawing beside
  # the game, at the cost of the game's GPU time, so the Guardian is held paused. The clocks are held at level 4,
  # the highest the headset sustains warm, so runs compare: left free it moves the GPU between 525 and 587 MHz as
  # it warms.
  saved_props=$(for k in guardian_pause cpuLevel gpuLevel; do printf '%s=%s ' "$k" "$(adb shell getprop "debug.oculus.$k" | tr -d '\r')"; done)
  logcat_pid=
  snoozed=
  restore_headset() {
    local kv
    set +e
    [ -z "$logcat_pid" ] || adb shell kill "$logcat_pid"
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
  # A Store or Library panel left open keeps the shell rendering beside the game and takes GPU time from it, which
  # no reading of the game's own App= time can subtract. A launch into a waking headset can also meet the shell's
  # controller check, with the controllers idle, or be paused as it starts, which crashes Godot; and while a
  # first-time tip (com.oculus.firsttimenux) is up the shell holds every launch. The Quest 3's guidebook posts tips
  # as toasts the shell draws beside the game. A fresh shell, with the panels, the tip and the guidebook closed,
  # starts with none of them, but replays every toast still posted, such as the Quest 2 library's long-press tip, for
  # 30 seconds beside the game: each is snoozed for an hour, which outlasts the run and lapses by itself.
  fresh_shell() {
    local app key
    for app in com.oculus.store com.oculus.panelapp.library com.oculus.firsttimenux com.oculus.guidebook com.oculus.vrshell; do
      adb shell am force-stop "$app"
    done
    sleep 10
    for key in $(adb shell dumpsys notification --noredact | sed -n 's/.*NotificationRecord(.* key=\([^:]*\): Notification(channel=vr_notifications_toast .*/\1/p'); do
      adb shell "cmd notification snooze --for 3600000 '$key'" > /dev/null
      snoozed="$snoozed $key"
    done
  }
  fresh_shell
  for try in 1 2 3; do
    adb shell am force-stop "$pkg"
    [ -z "$logcat_pid" ] || adb shell kill "$logcat_pid"
    adb logcat -c
    logcat_pid=$(adb shell "rm -f $log; nohup logcat -v threadtime -v epoch -f $log > /dev/null 2>&1 < /dev/null & echo \$!" | tr -d '\r')
    printf '%s\n' --script "$files/bench.json" --metrics "$dir/metrics.json" --capture-dir "$dir" --seed "$seed" \
      ${hosting:+--port "$hosting"} "${extra[@]}" > "$out/launch.args"
    adb push "$out/launch.args" "$files/launch.args" > /dev/null
    adb shell am start -n "$pkg/com.godot.game.GodotAppLauncher" > /dev/null
    sleep 15
    shows "activity activities" ResumedActivity "$pkg" && break
    [ "$try" -lt 3 ] || { adb pull "$log" "$out/logcat.txt" > /dev/null; echo "bench: the game would not start; see $out/logcat.txt" >&2; exit 1; }
    echo "bench: launch $try did not hold, restarting the shell" >&2
    fresh_shell
  done
  if [ "$players" -gt 1 ]; then
    join adb shell cat "$log" -- "$(adb shell ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1)"
  fi
  # The stress scene runs past 15 minutes on a Quest 2, so the run is given an hour. A dropped connection is no end.
  ended=
  SECONDS=0
  while [ "$SECONDS" -lt 3600 ]; do
    sleep 1
    [ "$(adb shell "pidof $pkg > /dev/null || echo gone" 2> /dev/null | tr -d '\r')" != gone ] || { ended=1; break; }
  done
  adb shell kill "$logcat_pid"
  logcat_pid=
  adb pull "$log" "$out/logcat.txt" > /dev/null
  [ -n "$ended" ] || { echo "bench: the game was still running after an hour; see $out/logcat.txt" >&2; exit 1; }
  adb pull "$dir/." "$out/" > /dev/null
elif [ $# -ge 4 ]; then
  device=frame
  rig=frame
  ssh "$2" 'set -e; rm -rf nestcombe-bench; mkdir nestcombe-bench; tar -xz -C nestcombe-bench; mkdir nestcombe-bench/nestcombe/log' < "$3"
  build=$(ssh -n "$2" cat nestcombe-bench/nestcombe/REVISION)
  same "$build"
  scp -q "$out/stress.json" "$2:nestcombe-bench/nestcombe/log/stress.json"
  trap 'ssh -n "$2" "[ ! -f nestcombe-bench/nestcombe/log/pid ] || kill \$(cat nestcombe-bench/nestcombe/log/pid)" || true; stop' EXIT
  # shellcheck disable=SC2016 # expanded on the headset
  "${@:4}" 'cd ~/nestcombe-bench/nestcombe
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
    status=0; timeout '"$limit"' ./nestcombe -- --script "$PWD/log/stress.json" --metrics "$PWD/log/metrics.json" --capture-dir "$PWD/log" --garden "$PWD/log/garden.save" --seed '"$seed${hosting:+ --port $hosting}"' > log/godot.log 2>&1 & echo $! > log/pid; wait $! || status=$?
    rm log/pid; echo "bench: $(cat REVISION) exit $status"; exit $status' &
  remote=$!
  if [ "$players" -gt 1 ]; then
    join ssh -n "$2" cat nestcombe-bench/nestcombe/log/godot.log -- \
      "$(ssh -n "$2" "ip -4 route get 1.1.1.1" | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
  fi
  wait "$remote" || game=$?
  scp -rq "$2:nestcombe-bench/nestcombe/log/*" "$out/"
else
  setsid env NESTCOMBE_QUIT_AFTER="$limit" "$here/render.sh" "$out/stress.json" "$out" -- --seed "$seed" ${hosting:+--port "$hosting"} > "$out/godot.log" 2>&1 &
  measured=$!
  [ "$players" -eq 1 ] || join cat "$out/godot.log" -- 127.0.0.1
  wait "$measured"
  measured=
fi
if [ "$players" -gt 1 ] && grep -qs "driver: until .* timed out" "$out"/godot.log "$out"/logcat.txt "$out"/guest*.log; then
  echo "bench: not all $players players joined" >&2
  exit 1
fi
scene=$(basename "${NESTCOMBE_SCENE:-stress.json}" .json)
record=$here/../perf/$rig/$scene/$(date -u +%Y%m%dT%H%M%SZ)-${build:0:7}.json
failed=
python3 - "$out" "$device" "$record" "$players" <<'PY' || failed=1
import bisect, json, os, re, sys
out, device, record, players = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
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
    # Only the game's process counts, the one printing as godot. Another process rendering during a phase, as the
    # shell does under an open panel, shares the GPU with the game, so that phase's times are not the game's.
    # A game that dies hands the compositor to the shell, which then renders in its phase: the death is the finding.
    # A hand the headset's cameras track, someone's near it, is drawn by the game with its tool and the tool's
    # preview, so a phase it shows in measures more than its scene.
    # Each line's phase is the metrics second it falls in, by the headset's clock: logcat drops lines under load, the
    # game's own label prints among them.
    ends = [s["unix"] for s in d["seconds"]]
    at = lambda t: d["seconds"][bisect.bisect_left(ends, t)]["label"] if t <= ends[-1] else "-"
    phase, game_pid, crash, done = "-", None, None, False
    shared, hands, handed = {}, set(), set()
    for line in open(os.path.join(out, "logcat.txt"), errors="replace"):
        m = re.match(r"\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+\w\s+(\S+)", line)
        if not m:
            continue
        label, pid = at(float(m.group(1))), m.group(2)
        if game_pid is None and m.group(3).startswith("godot"):
            game_pid = pid
        if label != "-":
            phase = label
        m = re.search(r"HANDTRACKING hand (\d+) status set to (\w+)", line)
        if m:
            (hands.add if m.group(2) == "Tracked" else hands.discard)(m.group(1))
        if hands and label != "-":
            handed.add(label)
        if pid == game_pid and "driver: done" in line:
            done = True
        m = re.search(r"Fatal signal \d+ \(\w+\).*", line)
        if m and pid == game_pid and crash is None:
            crash = f"bench: the game crashed during {phase}: {m.group(0).strip()}; see logcat.txt"
        m = re.search(r"VrApi.*FPS=(\d+)/\d+.*App=([\d.]+)ms", line)
        if m and label != "-" and pid == game_pid:
            gpu.setdefault(label, []).append(float(m.group(2)))
        elif m and label != "-":
            shared.setdefault(label, set()).add(pid)
    if crash or (game_pid and not done):
        sys.exit(crash or f"bench: the game died during {phase} before its script ended; see logcat.txt")
    if shared:
        sys.exit("bench: another process rendered during " + ", ".join(f"{k} (pid {', '.join(sorted(v))})" for k, v in shared.items()) + "; see logcat.txt")
    if handed:
        sys.exit("bench: the headset tracked a hand during " + ", ".join(sorted(handed)) + ", which the game drew; see logcat.txt")
    for v in gpu.values():
        v.pop(0)
    unmeasured = [name for name in phases if not gpu.get(name) and not name.startswith("sweep/")]
    if unmeasured:
        sys.exit("bench: no runtime GPU time for " + ", ".join(unmeasured) + "; see logcat.txt")
print(f"{device}: budget {budget['gpu_ms']:.2f} ms of GPU time a frame at {budget['refresh_hz']:.0f} Hz, held on a Quest")
landings = {}
for s in d["seconds"]:
    for w in s.get("landings", []):
        landings.setdefault(w["label"], []).append(w)
print(f"{'phase':18} {'frame p50':>9} {'p99':>7} {'late':>5} {'draws':>6} {'prims':>9} {'land max':>8} {'land late':>9} {'gpu ms':>7}")
over = []
summary = {}
for name, secs in phases.items():
    late = sum(s["late"] for s in secs)
    secs = secs[1:] or secs
    mid = lambda xs: sorted(xs)[len(xs) // 2] if xs else float("nan")
    windows = [{"frames": len(w["frames_ms"]), "max": w["max"], "late": w["late"]} for w in landings.get(name, [])]
    landed = f"{max(w['max'] for w in windows):8.2f} {sum(w['late'] for w in windows):9}" if windows else f"{'-':>8} {'-':>9}"
    row = f"{name:18} {mid([s['p50'] for s in secs]):9.2f} {max(s['p99'] for s in secs):7.2f} {late:5} {max(s['draws'] for s in secs):6} {max(s['prims'] for s in secs):9} {landed}"
    summary[name] = {"p50": mid([s["p50"] for s in secs]), "p99": max(s["p99"] for s in secs), "late": late,
                     "draws": max(s["draws"] for s in secs), "prims": max(s["prims"] for s in secs)}
    if windows:
        summary[name]["landings"] = windows
    if gpu.get(name):
        g = mid(gpu[name])
        summary[name]["gpu_ms"] = round(g, 3)
        row += f" {g:7.2f}"
        if device == "quest":
            held = g <= budget["gpu_ms"]
            row += " holds" if held else " OVER"
            if not held and not name.startswith("sweep/"):
                over.append(name)
    print(row)
os.makedirs(os.path.dirname(record), exist_ok=True)
with open(record, "w") as f:
    json.dump({"budget_gpu_ms": budget["gpu_ms"], **({"players": players} if players > 1 else {}), "phases": summary}, f, indent=1)
print(f"recorded {os.path.relpath(record)}")
if over:
    print("over budget: " + ", ".join(over))
    sys.exit(1)
PY
[ ! -f "$record" ] || python3 "$here/trend.py" "$rig" "$scene" || failed=1
[ "$game" = 0 ] || { echo "bench: the game exited $game; see $out/godot.log" >&2; exit 1; }
[ -z "$failed" ] || exit 1
