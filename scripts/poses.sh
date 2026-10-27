#!/usr/bin/env bash
# Another player's avatar standing, lying and sitting, as a host sees it: poses.sh OUT_DIR [AVATAR]. A guest joins the
# host and holds its head and hands where a person in each of Posture's poses held theirs (demo/poses-guest.json); the
# host draws the tracked head and hands as markers and captures the guest's avatar in each pose, a crouch it must show
# standing, and the blends between them (demo/poses-host.json), into OUT_DIR. AVATAR is a built-in's number or a VRM
# file the guest wears; by default built-in 0.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
avatar=${2:-0}
mkdir -p "$out"
rm -f "$out"/*.json "$out"/*.log "$out"/*.png
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 2560x1024x24 -nolisten tcp &
pids=($!)
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
export DISPLAY=$display
export VK_ICD_FILENAMES=${NESTCOMBE_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}
beacon=$((20000 + 4 * (RANDOM % 5000)))
first=$((7480 + 8 * (RANDOM % 7)))
wears=(--avatar "$avatar")
if [ -f "$avatar" ]; then
  rm -rf "$out/avatars"
  mkdir -p "$out/avatars"
  cp "$avatar" "$out/avatars/"
  wears=(--avatars "$out/avatars")
fi
# With a file to wear, the host waits until it shows the guest in it.
python3 - "$root/demo/poses-host.json" "$out/host.json" "$([ -f "$avatar" ] && echo 1 || echo 0)" <<'PY'
import json, sys
steps = json.load(open(sys.argv[1]))
if sys.argv[3] == "1":
    at = next(i for i, s in enumerate(steps) if s.get("players") == 2)
    steps.insert(at + 1, {"op": "until", "worn": 1, "seconds": 120})
json.dump(steps, open(sys.argv[2], "w"))
PY
cp "$root/demo/poses-guest.json" "$out/guest.json"
game() {
  local name=$1
  shift
  timeout 400 godot4 --path "$root/game" --resolution 1200x900 --xr-mode off -- --desktop --script "$out/$name.json" \
    --capture-dir "$out" --beacon-port "$beacon" --port "$first" --quit-after 360 "$@" >"$out/$name.log" 2>&1 &
  pids+=($!)
}
game host --avatar 0
for _ in $(seq 600); do
  port=$(sed -n 's/^session: hosting on port //p' "$out/host.log" | head -n1)
  [ -n "$port" ] && break
  sleep 0.1
done
[ -n "$port" ] || { echo "poses: the host never opened its garden; see $out/host.log"; exit 1; }
game guest --host-port "$port" "${wears[@]}"
status=0
for pid in "${pids[@]:1}"; do wait "$pid" || status=1; done
for name in host guest; do
  if grep -qE "SCRIPT ERROR|timed out|handle_crash" "$out/$name.log"; then echo "poses: $name failed; see $out/$name.log"; status=1; fi
done
ls "$out"/pose-*.png >/dev/null 2>&1 || { echo "poses: no captures in $out"; status=1; }
exit "$status"
